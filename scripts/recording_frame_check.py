#!/usr/bin/env python3
"""QA-011 Batch 6: pulls the recordings and stills a device test made and checks what is in the files.

The recording device tests (B08RecordingDeviceTests, B08ShareDeviceTests) print one line per file they leave in the
app's container:

    RECORDING-CHECK {"task": "REC-016-T13", "label": "30 s", "dir": "tmp/QA011-REC016", "prefix": "Visualizer Recording",
                     "suffix": ".mp4", "notBefore": "2026-11-18 at 14.05.30", "checks": {"atoms": {"absent": ["moof"]}}}

`run` reads a finished xcodebuild log, finds each file in the app's container with `devicectl device info files`,
copies it off the device (`devicectl device copy from`) and runs its checks:

* `codec`, `minDuration`, `maxDuration`, `audioTrack`: the tracks AVFoundation reads (Swift helper `info`);
* `atoms`: the file's top-level MP4 boxes (`moov` present, no `moof`: not fragmented; REC-016-T13);
* `image`: `sips -g all` reads the still (format, size; decoding it is the check; REC-001-T19);
* `ocrAbsent`, `ocrAny`, `ocrPattern`: Vision text recognition of frames (REC-009-T11 status lines absent; MED-011-T13
  the clock; MED-012-T14 the countdown);
* `centre`: Pearson correlation of a frame's block-mean luma with the grid the test took from a screenshot's centre
  crop at the same moment (REC-014-T15);
* `alignment`: audio clicks against luma flashes (beat rings), median offset within `maxMs` (REC-004-T19, S5);
* `audioNonSilent`: the audio track's loudest bin (a Microphone recording of the Mac's tone; REC-004-T19);
* `qa008`: `RecordingValidationCorpusTests.testExternalRecording` on the file (QA-008-T10);
* `absent: true`: no matching file is left (REC-010-T13's delete).

    python3 scripts/recording_frame_check.py run --log Build/b08-D1.log --device D1 [--out Build/recording-checks/D1]
    python3 scripts/recording_frame_check.py check --file x.mp4 --spec '{"checks": {"atoms": {"absent": ["moof"]}}}'

The Swift helper (scripts/fixtures/recording_inspect.swift) is compiled once into Build/tools. Writes only under
--out; reads only the test app's own container. Simulator files are never evidence.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import statistics
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = "org.projectmios.ProjectMiOS"
DEVICES = {"D1": "iPhone15,4", "D2": "iPad17,3", "D3": "iPad15,7"}
HELPER_SOURCE = ROOT / "scripts" / "fixtures" / "recording_inspect.swift"
HELPER = ROOT / "Build" / "tools" / "recording_inspect"
MARK = "RECORDING-CHECK "
STAMP = re.compile(r"(\d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2})")


# MARK: The log and the device's files

def parse_checks(lines) -> list[dict]:
    """Every `RECORDING-CHECK {json}` line (xcodebuild prefixes are ignored; a broken line is skipped)."""
    found = []
    for line in lines:
        i = line.find(MARK)
        if i < 0:
            continue
        try:
            found.append(json.loads(line[i + len(MARK):].strip()))
        except json.JSONDecodeError:
            continue
    return found


def stamp(name: str) -> str | None:
    """The "2026-11-18 at 14.05.32" in an app-made file name (recordings, frames), else None."""
    m = STAMP.search(name)
    return m.group(1) if m else None


def pick(names: list[str], prefix: str = "", suffix: str = "", not_before: str | None = None,
         exact: str | None = None) -> str | None:
    """The newest file name in the folder with `prefix` and `suffix` (and a stamp not before `not_before`)."""
    leaf = [n.rsplit("/", 1)[-1] for n in names]
    if exact is not None:
        return exact if exact in leaf else None
    candidates = [n for n in leaf if n.startswith(prefix) and n.endswith(suffix)]
    if not_before:
        candidates = [n for n in candidates if (stamp(n) or "") >= not_before]
    candidates.sort(key=lambda n: (stamp(n) or "", n))
    return candidates[-1] if candidates else None


def device_ids(listing: dict) -> dict[str, str]:
    out = {}
    by_type = {d.get("hardwareProperties", {}).get("productType"): d.get("identifier", "")
               for d in listing.get("result", {}).get("devices", [])}
    for name, product in DEVICES.items():
        if product in by_type:
            out[name] = by_type[product]
    return out


def devicectl_json(args: list[str]) -> dict:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "out.json"
        subprocess.run(["xcrun", "devicectl", *args, "--json-output", str(out)], check=True, capture_output=True)
        return json.loads(out.read_text())


def list_files(identifier: str, directory: str) -> list[str]:
    try:
        listing = devicectl_json(["device", "info", "files", "--device", identifier, "--domain-type", "appDataContainer",
                                  "--domain-identifier", BUNDLE, "--subdirectory", directory])
    except subprocess.CalledProcessError:
        return []   # the folder does not exist
    return [f.get("relativePath", "") for f in listing.get("result", {}).get("files", [])]


def pull_command(identifier: str, source: str, destination: Path) -> list[str]:
    return ["xcrun", "devicectl", "device", "copy", "from", "--device", identifier, "--domain-type", "appDataContainer",
            "--domain-identifier", BUNDLE, "--source", source, "--destination", str(destination)]


# MARK: File facts

def top_level_atoms(data: bytes) -> list[str]:
    """The top-level ISO BMFF box types in order (32-bit sizes, 64-bit `largesize`, size 0 = to the end)."""
    atoms, offset = [], 0
    while offset + 8 <= len(data):
        size, kind = struct.unpack(">I4s", data[offset:offset + 8])
        header = 8
        if size == 1:
            if offset + 16 > len(data):
                break
            size = struct.unpack(">Q", data[offset + 8:offset + 16])[0]
            header = 16
        elif size == 0:
            size = len(data) - offset
        atoms.append(kind.decode("latin-1"))
        if size < header:
            break
        offset += size
    return atoms


def file_atoms(path: Path) -> list[str]:
    """Top-level boxes read from the file's headers only (mdat bodies are skipped, not loaded)."""
    atoms = []
    with path.open("rb") as f:
        total = path.stat().st_size
        offset = 0
        while offset + 8 <= total:
            f.seek(offset)
            head = f.read(16)
            size, kind = struct.unpack(">I4s", head[:8])
            header = 8
            if size == 1:
                size, header = struct.unpack(">Q", head[8:16])[0], 16
            elif size == 0:
                size = total - offset
            atoms.append(kind.decode("latin-1"))
            if size < header:
                break
            offset += size
    return atoms


def parse_sips(text: str) -> dict:
    """`sips -g all` output → {"format": "png", "pixelWidth": 1179, …} (numbers as int where they are)."""
    out = {}
    for line in text.splitlines()[1:]:
        if ":" not in line:
            continue
        key, value = (part.strip() for part in line.split(":", 1))
        out[key] = int(value) if value.isdigit() else value
    return out


# MARK: Measures

def normalise(text: str) -> str:
    """OCR text for matching: lower case, no spaces, '.' read as ':' (Vision reads 14:05 as 14.05 at times)."""
    return text.lower().replace(" ", "").replace(".", ":")


def ocr_hits(frames: list[dict], strings: list[str]) -> list[tuple[float, str, str]]:
    """(time, recognised text, matched string) for each recognised text that contains one of `strings`."""
    wanted = [(s, normalise(s)) for s in strings if s.strip()]
    hits = []
    for frame in frames:
        for text in frame.get("texts", []):
            n = normalise(text)
            for original, w in wanted:
                if w and w in n:
                    hits.append((frame.get("t", -1), text, original))
    return hits


def ocr_pattern_frames(frames: list[dict], pattern: str) -> list[tuple[float, str]]:
    rx = re.compile(pattern)
    return [(f.get("t", -1), t) for f in frames for t in f.get("texts", []) if rx.search(t.replace(".", ":"))]


def pearson(a: list[float], b: list[float]) -> float:
    if len(a) != len(b) or len(a) < 2:
        return 0.0
    ma, mb = statistics.fmean(a), statistics.fmean(b)
    da = [x - ma for x in a]
    db = [y - mb for y in b]
    num = sum(x * y for x, y in zip(da, db))
    den = (sum(x * x for x in da) * sum(y * y for y in db)) ** 0.5
    return num / den if den else 0.0


def click_onsets(peaks: list[float], bin_ms: float, start: float = 0.0, ratio: float = 0.3,
                 min_gap: float = 0.25) -> list[float]:
    """Times (s) where the audio peak envelope rises above `ratio` × its maximum, at most one per `min_gap`."""
    if not peaks:
        return []
    threshold = max(peaks) * ratio
    onsets, last = [], -1e9
    for i, value in enumerate(peaks):
        t = start + i * bin_ms / 1000
        if value >= threshold and (i == 0 or peaks[i - 1] < threshold) and t - last >= min_gap:
            onsets.append(round(t, 4))
            last = t
    return onsets


def flash_onsets(frames: list[list[float]], ratio: float = 0.5, min_gap: float = 0.25) -> list[float]:
    """Frame times where the mean luma jumps by at least `ratio` × the largest frame-to-frame rise."""
    rises = [(frames[i][0], frames[i][1] - frames[i - 1][1]) for i in range(1, len(frames))]
    if not rises:
        return []
    biggest = max(r for _, r in rises)
    if biggest <= 0:
        return []
    onsets, last = [], -1e9
    for t, rise in rises:
        if rise >= biggest * ratio and t - last >= min_gap:
            onsets.append(round(t, 4))
            last = t
    return onsets


def alignment(clicks: list[float], flashes: list[float], before: float = 0.1, after: float = 0.25) -> dict:
    """For each click the first flash within [click − before, click + after]: offsets (ms, flash − click)."""
    offsets = []
    for c in clicks:
        near = [f for f in flashes if c - before <= f <= c + after]
        if near:
            offsets.append(round((near[0] - c) * 1000, 1))
    return {"clicks": len(clicks), "flashes": len(flashes), "paired": len(offsets), "offsetsMs": offsets,
            "medianMs": statistics.median(offsets) if offsets else None}


# MARK: Checks

class Inspector:
    """The compiled Swift helper (rebuilt when its source is newer)."""

    def __init__(self, binary: Path = HELPER):
        self.binary = binary

    def ensure(self) -> None:
        if not self.binary.exists() or self.binary.stat().st_mtime < HELPER_SOURCE.stat().st_mtime:
            self.binary.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["xcrun", "swiftc", "-O", "-suppress-warnings", str(HELPER_SOURCE), "-o", str(self.binary)],
                           check=True)

    def __call__(self, *args) -> dict:
        self.ensure()
        out = subprocess.run([str(self.binary), *map(str, args)], capture_output=True, text=True)
        try:
            return json.loads(out.stdout.strip().splitlines()[-1])
        except (json.JSONDecodeError, IndexError):
            return {"error": out.stderr.strip() or "no output"}


def sips(path: Path) -> dict:
    out = subprocess.run(["sips", "-g", "all", str(path)], capture_output=True, text=True)
    return parse_sips(out.stdout) if out.returncode == 0 else {"error": out.stderr.strip()}


def qa008(path: Path, spec: dict) -> dict:
    env = {"QA008_RECORDING": str(path)}
    if spec.get("expectAudio"):
        env["QA008_EXPECT_AUDIO"] = "1"
    if spec.get("fps"):
        env["QA008_FPS"] = str(spec["fps"])
    out = subprocess.run(["swift", "test", "--package-path", str(ROOT / "Packages" / "Compositor"), "--filter",
                          "testExternalRecording"], capture_output=True, text=True, env={**os.environ, **env})
    tail = (out.stdout + out.stderr).strip().splitlines()[-12:]
    return {"ok": out.returncode == 0, "tail": tail}


def evaluate(path: Path, checks: dict, inspect=None, read_sips=sips, run_qa008=qa008) -> dict:
    """Runs `checks` on the local file `path`; returns {"ok": bool, "results": {name: {...}}}."""
    inspect = inspect or Inspector()
    results: dict[str, dict] = {}
    info = None

    def facts() -> dict:
        nonlocal info
        if info is None:
            info = inspect("info", path)
        return info

    if "codec" in checks:
        codec = facts().get("video", {}).get("codec")
        results["codec"] = {"ok": codec == checks["codec"], "codec": codec}
    if "minDuration" in checks or "maxDuration" in checks:
        d = facts().get("duration", -1)
        ok = d >= checks.get("minDuration", -1e9) and d <= checks.get("maxDuration", 1e9)
        results["duration"] = {"ok": ok, "duration": d, "frames": facts().get("video", {}).get("frames")}
    if "audioTrack" in checks:
        has = "audio" in facts()
        results["audioTrack"] = {"ok": has == bool(checks["audioTrack"]), "audio": facts().get("audio")}
    if "atoms" in checks:
        atoms = file_atoms(path)
        present = checks["atoms"].get("present", [])
        absent = checks["atoms"].get("absent", [])
        results["atoms"] = {"ok": all(a in atoms for a in present) and not any(a in atoms for a in absent), "atoms": atoms}
    if "image" in checks:
        s = read_sips(path)
        want = checks["image"]
        ok = "error" not in s and s.get("format") == want.get("format", s.get("format"))
        for key in ("pixelWidth", "pixelHeight"):
            if key in want:
                ok = ok and s.get(key) == want[key]
        if "minPixels" in want:
            ok = ok and int(s.get("pixelWidth", 0)) * int(s.get("pixelHeight", 0)) >= want["minPixels"]
        results["image"] = {"ok": ok, "sips": {k: s.get(k) for k in ("format", "pixelWidth", "pixelHeight", "hasAlpha",
                                                                     "space", "error") if k in s}}
    for name in ("ocrAbsent", "ocrAny", "ocrPattern"):
        if name not in checks:
            continue
        spec = checks[name]
        times = spec.get("times") or [0.5]
        frames = inspect("ocr", path, ",".join(str(t) for t in times)).get("frames", [])
        texts = [{"t": f.get("t"), "texts": f.get("texts", [])} for f in frames]
        if name == "ocrAbsent":
            hits = ocr_hits(frames, spec.get("strings", []))
            results[name] = {"ok": bool(frames) and not hits, "hits": hits, "frames": texts}
        elif name == "ocrAny":
            hits = ocr_hits(frames, spec.get("strings", []))
            results[name] = {"ok": len({h[0] for h in hits}) >= spec.get("minFrames", 1), "hits": hits, "frames": texts}
        else:
            hits = ocr_pattern_frames(frames, spec["pattern"])
            ok = len({h[0] for h in hits}) >= spec.get("minFrames", 1)
            if spec.get("last"):
                last = [h for h in hits if h[0] == max(times)]
                ok = ok and any(normalise(spec["last"]) in normalise(t) for _, t in last)
            results[name] = {"ok": ok, "hits": hits, "frames": texts}
    if "centre" in checks:
        spec = checks["centre"]
        grid = inspect("grid", path, spec["time"], spec["cols"], spec["rows"])
        r = pearson([float(v) for v in grid.get("values", [])], [float(v) for v in spec["values"]])
        results["centre"] = {"ok": r >= spec.get("minCorrelation", 0.8), "correlation": round(r, 3),
                             "fileGrid": grid.get("values")}
    if "alignment" in checks:
        spec = checks["alignment"]
        env = inspect("envelope", path, 1)
        clicks = click_onsets(env.get("peaks", []), env.get("binMs", 1), env.get("start", 0))
        flashes = flash_onsets(inspect("luma", path).get("frames", []))
        a = alignment(clicks, flashes)
        a["ok"] = a["medianMs"] is not None and abs(a["medianMs"]) <= spec.get("maxMs", 40) \
            and a["paired"] >= spec.get("minPairs", 4)
        results["alignment"] = a
    if "audioNonSilent" in checks:
        env = inspect("envelope", path, 10)
        peak = max(env.get("peaks", [0]) or [0])
        results["audioNonSilent"] = {"ok": peak >= checks["audioNonSilent"].get("minPeak", 0.01), "peak": peak}
    if "qa008" in checks:
        results["qa008"] = run_qa008(path, checks["qa008"])
    return {"ok": all(r.get("ok") for r in results.values()), "results": results}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run_entry(entry: dict, identifier: str, out: Path, dry_run: bool = False, lister=list_files, runner=subprocess.run,
              evaluator=evaluate) -> dict:
    directory = entry.get("dir", "Documents")
    names = lister(identifier, directory)
    name = pick(names, entry.get("prefix", ""), entry.get("suffix", ""), entry.get("notBefore"), entry.get("name"))
    result = {"task": entry.get("task"), "label": entry.get("label"), "dir": directory, "file": name}
    if entry.get("absent"):
        result["ok"] = name is None
        return result
    if name is None:
        result.update(ok=False, error=f"no {entry.get('prefix', '')}…{entry.get('suffix', '')} in {directory}")
        return result
    local = out / "files" / f"{entry.get('task', 'x')}-{name}"
    command = pull_command(identifier, f"{directory}/{name}", local)
    if dry_run:
        result.update(ok=True, command=command)
        return result
    local.parent.mkdir(parents=True, exist_ok=True)
    pulled = runner(command, capture_output=True, text=True)
    if getattr(pulled, "returncode", 1) != 0 or not local.exists():
        result.update(ok=False, error=f"copy failed: {getattr(pulled, 'stderr', '')}".strip())
        return result
    result["sha256"] = sha256(local)
    result["local"] = str(local.relative_to(ROOT)) if local.is_relative_to(ROOT) else str(local)
    result.update(evaluator(local, entry.get("checks", {})))
    return result


def run(log: Path, device: str, out: Path, dry_run: bool = False) -> int:
    entries = parse_checks(log.read_text(errors="replace").splitlines())
    if not entries:
        print(f"recording_frame_check: no RECORDING-CHECK lines in {log}")
        return 1
    ids = device_ids(devicectl_json(["list", "devices"]))
    if device not in ids:
        print(f"recording_frame_check: {device} is not connected")
        return 1
    out.mkdir(parents=True, exist_ok=True)
    results = []
    for entry in entries:
        r = run_entry(entry, ids[device], out, dry_run=dry_run)
        print("RECORDING-CHECK-RESULT " + json.dumps({k: r.get(k) for k in ("task", "label", "file", "ok", "error")},
                                                    sort_keys=True))
        results.append(r)
    report = {"device": device, "log": str(log), "logSha256": sha256(log), "results": results,
              "ok": all(r.get("ok") for r in results)}
    if not dry_run:
        (out / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print(f"recording_frame_check: {sum(r.get('ok', False) for r in results)}/{len(results)} passed, "
              f"report {out / 'report.json'}")
    return 0 if report["ok"] else 1


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="command", required=True)
    r = sub.add_parser("run", help="pull and check every file a run's log names")
    r.add_argument("--log", type=Path, required=True)
    r.add_argument("--device", choices=sorted(DEVICES), required=True)
    r.add_argument("--out", type=Path)
    r.add_argument("--dry-run", action="store_true", help="list the files and copy commands; copy nothing")
    c = sub.add_parser("check", help="run checks on a local file")
    c.add_argument("--file", type=Path, required=True)
    c.add_argument("--spec", required=True, help='JSON: {"checks": {…}}')
    args = p.parse_args(argv)
    if args.command == "run":
        return run(args.log, args.device, args.out or ROOT / "Build" / "recording-checks" / args.device, args.dry_run)
    result = evaluate(args.file, json.loads(args.spec).get("checks", {}))
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
