#!/usr/bin/env python3
"""QA-011: run the final physical device matrix on D1-D3 (or rehearse it on a simulator) and write a signed,
hashed run record per device (specs/313-qa-011-final-device-matrix).

    python3 scripts/run_device_matrix.py --device D1 --dry-run         # print every command; writes nothing
    python3 scripts/run_device_matrix.py --device D1 [--build]         # the device run (owner present, unlocked)
    python3 scripts/run_device_matrix.py --device all                  # D1, D2, D3 in turn
    python3 scripts/run_device_matrix.py --simulator <udid> --app <Debug simulator .app>   # rehearsal, not evidence
    python3 scripts/run_device_matrix.py verify docs/test-reports/qa-011/runs/D1/<run-id>/record.json
    python3 scripts/run_device_tests.py matrix --device D1             # the same, through the device runner

The cases (CASES) are the category (a) work of docs/test-reports/qa-011/device-inventory.json: AutomationRunner
modes, launch modes, the QA-010 threshold judge, and on-device XCTest suites and benches. Each case runs on the
devices of the tasks it closes (read from the inventory). Order: one fresh install of the measurement build, the
app's automation cases, package XCTest, and last the app-hosted XCTest suite (it replaces the installed app).

The record (docs/test-reports/qa-011/runs/<label>/<run-id>/record.json, contract in the spec's
contracts/run-record.md) carries the device model, OS version and build, the app's version, build and commit, the
code signature's identity and team as `codesign -dv` reports them, every case's status, commands and artifacts with
SHA-256 hashes, and its own hash (also in record.json.sha256). Small JSON reports are copied next to the record
(committed); xcresult bundles and logs stay under --work-dir (default Build/qa-011, gitignored).

Never changes signing: package suites use Configs/Signing.xcconfig, which only includes the owner's gitignored
local file. A simulator rehearsal is never evidence (Constitution X).
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_device_tests as rdt  # noqa: E402
import check_performance_thresholds as cpt  # noqa: E402
import import_device_goldens as idg  # noqa: E402
from mac_driver import xctrace as xt  # noqa: E402

ROOT = rdt.ROOT
RUNS = ROOT / "docs/test-reports/qa-011/runs"
INVENTORY = ROOT / "docs/test-reports/qa-011/device-inventory.json"
SIGNING_XCCONFIG = ROOT / "Configs/Signing.xcconfig"
RECORD_KIND = "projectM-iOS.qa011.deviceRun"
LABELS = ("D1", "D2", "D3")
STATUSES = ("pass", "fail", "timeout", "blocked", "error", "skipped", "not-run")
LOCK_RE = re.compile(r"(?i)(device is locked|is locked|passcode[- ]protected|unlock (?:the|your|this) device|"
                     r"\bLocked\b)")
COMMIT_LIMIT = 1_000_000   # pulled reports up to this size are copied next to the record (committed)
RENDERERLAB_BUNDLE = "org.projectmios.RendererLab"
RENDERERLAB_PROJECT = ROOT / "RendererLab.xcodeproj"
RENDERERLAB_BUILD = ROOT / "Build/rendererlab"


def case(id: str, kind: str, title: str, closes: list[str], timeout: int, **params) -> dict:
    return {"id": id, "kind": kind, "title": title, "closes": closes, "timeoutSeconds": timeout, **params}


# In run order. `closes`: the tasks the case fully closes (category a); `partOf`: tasks of which it scripts a part.
# `onDemand`: never in a plain run, only when named with --only (long benches, a prompt, recording goldens).
# `prompts`: the case raises that permission prompt unless it was answered on the installed app, so it refuses to run
# after this run's fresh install (owner rule 14, amended 2026-11-18: prompts belong to the prompt-flow batch).
CASES: list[dict] = [
    # No case needs a person (owner ruling 2026-11-15): AUD-014's sc009 lifecycle script triggers the one-time
    # microphone prompt after the fresh install, so it moved to owner session B05 (the AutomationRunner mode stays).
    case("autorun-perf001", "autorun", "AutomationRunner perf001: per-stage frame timings, 1 s frame-rate windows, "
         "PERF-007 drops", ["PERF-001-T16", "PERF-002-T13", "QA-010-T12"], 300, mode="perf001",
         prefix="automation-perf001", wait=240),
    case("launches-sc015", "launches", "sc015 cold launches (10 recorded) for the QA-010 launch budget",
         ["QA-010-T12"], 400, mode="sc015", repeat=10),
    case("warmstart-perf009", "warmstart", "PERF-009 cold and warm launches (10 each), medians",
         ["PERF-009-T16"], 600, repeat=10),
    case("autorun-perf001-glow", "autorun", "AutomationRunner perf001 on the circular spectrum with the glow on: the "
         "export carries the effect quality level at the device's real thermal state (PERF-003)", [], 300,
         partOf=["PERF-003-T15"], mode="perf001", prefix="automation-perf001", wait=240,
         env={"PROJECTM_VISUAL": "circularSpectrum", "PROJECTM_GLOW": "1"}, expect="frameTimings.effectQuality"),
    case("autorun-pre005", "autorun", "AutomationRunner pre005: motion scores of 200 real thumbnails (evenly spaced "
         "over the library), percentiles and class counts at today's thresholds", [], 900, partOf=["PRE-005-T17"],
         mode="pre005", prefix="automation-pre005", wait=840),
    case("autorun-sc009", "autorun", "AutomationRunner sc009: In-App Playback and Microphone lifecycle scripts "
         "(watchdog: a partial report names the stalled phase)", ["AUD-014-T32"], 300, mode="sc009",
         prefix="automation-sc009", wait=240, prompts="microphone", onDemand=True),
    case("rendererlab-flashcost", "rendererlab", "RendererLab flashcost: strobe safety pass cost per starter preset, "
         "the pass on the frame it processes (GPU timer query plus CPU encoding; on minus off reported), at most 2 ms "
         "per frame (FX-019-S6)", [], 1200, partOf=["FX-019-T22"],
         wait=1080, limitMs=2.0),
    case("xctrace-perf004", "xctrace", "Instruments Logging (os_signpost): PERF-004 texture allocations only at the "
         "start and within 3 s of a rotation", ["PERF-004-T16"], 900, verdict="perf004",
         # 50 s: the app ends the recording by exiting (about 33 s, 38 s when its playback start hung 5 s on D1),
         # never the time limit; xctrace then needs 3-5 minutes on D1 to save (`xt.SAVE_QUIET`, 2026-11-24).
         runs=[{"name": "perf004", "template": "Logging", "seconds": 50, "mode": "perf004",
                # The Text visual: a compositor visual (shared texture pool) that needs no permission (2026-11-23).
                "env": {"PROJECTM_VISUAL": "text"},
                "tables": [xt.SIGNPOST_SCHEMA]}]),
    case("xctrace-perf011", "xctrace", "Instruments Metal System Trace: no GPU intervals and a lower footprint 10 s "
         "after backgrounding (In-App Playback), frames within 2 s of the return", [], 900, partOf=["PERF-011-T21"],
         verdict="perf011",
         # Times count from the app's launch (`wait_for_launch`): 10 s in front, 16 s away (the check reads the
         # last 6), 14 s back; the time limit leaves the app room to exit by itself first. Metal System Trace wrote
         # 1.98 GB while the app drew for about 35 s on D1 (2026-11-23), so it draws for about 24 s now.
         runs=[{"name": "perf011", "template": "Metal System Trace", "seconds": 70, "mode": "perf011",
                "env": {"PROJECTM_SECONDS": "40"}, "instruments": ["os_signpost"],
                "tables": [xt.SIGNPOST_SCHEMA, xt.GPU_SCHEMA], "background": [10, 26]}]),
    case("xctrace-perf008", "xctrace", "Instruments Power Profiler: 5 min Standard, then 5 min Battery saver "
         "(In-App Playback); frame time and energy per minute", [], 2400, partOf=["PERF-008-T16"], verdict="perf008",
         onDemand=True,
         runs=[{"name": f"perf008-{p}", "template": "Power Profiler", "seconds": 320, "mode": "perf008",
                "env": {"PROJECTM_POWER_PROFILE": p, "PROJECTM_SECONDS": "300"}, "instruments": ["os_signpost"],
                "tables": [xt.SIGNPOST_SCHEMA], "powerTables": True} for p in ("standard", "batterySaver")]),
    case("autorun-perf012", "autorun", "AutomationRunner perf012: a 1-minute overlay session, then the PERF-012 "
         "report (frame-interval percentiles, peak memory, audio age) for the QA-010 judge", [], 300,
         partOf=["QA-010-T12"], mode="perf012", prefix="performance-perf012", wait=180),
    case("thresholds", "thresholds", "QA-010 judge over the pulled perf001 and sc015 reports (plus any PERF-012 "
         "export given with --perf012-report)", ["QA-010-T12"], 120),
    case("xctest-goldens", "xctest", "RenderGoldens suite on the device GPU (goldens report pending without a "
         "device golden class; short soak included)", ["QA-003-T17"], 900, package="RenderGoldens"),
    case("xctest-soak-600", "xctest", "QA-006 long scene soak, 600 s simulated", ["QA-006-T13"], 1200,
         package="RenderGoldens", only=["RenderGoldensTests/RenderSoakTests/testOnDemandLongSoak"],
         env={"QA006_SOAK_SECONDS": "600"}),
    case("xctest-materials", "xctest", "SHD-004 material variants on the device GPU family (Detailed needs "
         "family 9; Standard fallback with the notice)", ["SHD-004-T20"], 900, package="Compositor",
         only=["ProceduralMaterialsTests/MaterialVariantSwitchTests"]),
    case("xctest-angle-layer", "xctest", "CMP-001 ProjectMLayerTests and the client-buffer spike tests on the "
         "device", [], 900, partOf=["CMP-001-T20"], package="ANGLERendering",
         only=["ANGLERenderingTests/ProjectMLayerTests", "ANGLERenderingTests/ClientBufferSpikeTests"]),
    case("xctest-pre012-limits", "xctest", "PRE-012 worst-case preset shapes at the static limits and at twice them "
         "do not crash the trial thread or the visible engine (device stack sizes)", [], 600, partOf=["PRE-012-T31"],
         package="ANGLERendering",
         only=["ANGLERenderingTests/PresetTrialRunnerTests/testPresetsAtTheStaticLimitsDoNotCrashTheProcess",
               "ANGLERenderingTests/PresetTrialRunnerTests/testPresetsAtTwiceTheStaticLimitsDoNotCrashEither"]),
    case("bench-shd002", "xctest", "SHD-002 12-node graph GPU cost (SHD002_BENCH)", ["SHD-002-T24"], 900,
         package="Compositor", only=["GeneratorGraphTests/GraphCostBench"], env={"SHD002_BENCH": "1"},
         configuration="Release"),
    case("bench-rec003-encoder", "xctest", "REC-003 encoder throughput at native size, 60 fps, 40 Mbit/s: 32BGRA "
         "against 4:2:0 input, HEVC and H.264 (REC003_ENCODER_BENCH)", [], 300, partOf=["REC-003-T23"],
         package="Compositor", only=["FrameRecordingTests/EncoderThroughputBench"], env={"REC003_ENCODER_BENCH": "1"},
         configuration="Release"),
    case("bench-cmp008", "xctest", "CMP-008 full-screen gradient layer GPU time (CMP008_BENCH)", ["CMP-008-T19"],
         900, package="Compositor", only=["CompositorTests/LayerGradientCompositeTests/testGradientGPUTimeBench"],
         env={"CMP008_BENCH": "1"}, configuration="Release"),
    case("bench-cmp009", "xctest", "CMP-009 full-screen luma-keyed layer GPU time (CMP009_BENCH)", ["CMP-009-T19"],
         900, package="Compositor", only=["CompositorTests/LayerLumaKeyCompositeTests/testLumaKeyGPUTimeBench"],
         env={"CMP009_BENCH": "1"}, configuration="Release"),
    case("bench-cmp010", "xctest", "CMP-010 full-screen colour-keyed layer GPU time (CMP010_BENCH)",
         ["CMP-010-T19"], 900, package="Compositor",
         only=["CompositorTests/LayerColorKeyCompositeTests/testColorKeyGPUTimeBench"],
         env={"CMP010_BENCH": "1"}, configuration="Release"),
    case("bench-expression", "xctest", "SHD-010 per-frame expression cost, Release (PARAMETER_EXPRESSION_BENCH)",
         ["SHD-010-T13"], 900, package="ParameterGraph",
         only=["ParameterExpressionTests/ExpressionCompileWorkTests/testInformationalHostCost"],
         env={"PARAMETER_EXPRESSION_BENCH": "1"}, configuration="Release"),
    case("xctest-goldens-record", "xctest", "RenderGoldens suite recording this device model's goldens "
         "(RECORD_DEVICE_GOLDENS); imported into Packages/RenderGoldens/Goldens/<class> for a commit", [], 900,
         partOf=["QA-003-T17"], package="RenderGoldens", only=["RenderGoldensTests/GoldenRenderSuiteTests"],
         env={"RECORD_DEVICE_GOLDENS": "1"}, importGoldens=True, onDemand=True),
    case("xctest-offline-export", "xctest", "REC-013 two offline exports of the fixture match frame checksums "
         "(app-hosted; replaces the installed app, so it runs last)", ["REC-013-T14"], 900, app=True,
         only=["projectM-iOSTests/OfflineExportAcceptanceTests"]),
]
CASE_IDS = [c["id"] for c in CASES]
# Cases that stay release evidence on these devices even when every task they closed is done (2026-11-16: closing
# CMP-001-T20 left xctest-angle-layer on no device and failed CI run 43918880546).
DEFAULT_DEVICES = {"autorun-perf001": LABELS, "launches-sc015": LABELS, "thresholds": LABELS, "xctest-angle-layer": LABELS,
                   "bench-rec003-encoder": ["D1", "D3"], "autorun-sc009": ["D1", "D3"]}


# MARK: - Which cases run where (from the inventory)

def case_devices(inventory: dict | None) -> dict[str, list[str]]:
    """Case id → sorted devices: the union of the devices of the open or optional tasks that list the case."""
    out: dict[str, set[str]] = {c["id"]: set(DEFAULT_DEVICES.get(c["id"], ())) for c in CASES}
    for task in (inventory or {}).get("tasks", []):
        if task.get("status") == "waived":
            continue
        for cid in task.get("matrixCases", []):
            if cid in out:
                out[cid].update(task.get("devices", []))
    # No inventory, or a case whose tasks are all closed: it still runs on D1 (the reference device) as evidence.
    for cid, devices in out.items():
        if not inventory or not devices:
            devices.add("D1")
    return {cid: sorted(devices) for cid, devices in out.items()}


def load_inventory(path: Path = INVENTORY) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def plan(label: str | None, devices_by_case: dict[str, list[str]], only: set[str] | None = None) -> list[dict]:
    """The cases for one device (label None: a rehearsal runs every case), in run order."""
    chosen = []
    for c in CASES:
        if only and c["id"] not in only:
            continue
        if c.get("onDemand") and not (only and c["id"] in only):
            continue
        if label is None or label in devices_by_case.get(c["id"], []):
            chosen.append(c)
    return chosen


# MARK: - Hashing and the record

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def sha256_path(path: Path) -> str:
    """A file's SHA-256, or for a folder the SHA-256 of its sorted `relpath NUL sha256 LF` lines."""
    if path.is_file():
        return sha256_file(path)
    lines = []
    for p in sorted(q for q in path.rglob("*") if q.is_file()):
        lines.append(f"{p.relative_to(path).as_posix()}\0{sha256_file(p)}\n")
    return hashlib.sha256("".join(lines).encode("utf-8")).hexdigest()


def path_bytes(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file())


def display_path(path: Path) -> str:
    """Repository-relative when inside the repository (symlinks not resolved), else absolute."""
    try:
        return path.absolute().relative_to(ROOT).as_posix()
    except ValueError:
        return str(path.absolute())


def artifact(path: Path, committed: bool) -> dict:
    return {"path": display_path(path), "kind": "folder" if path.is_dir() else "file", "bytes": path_bytes(path),
            "sha256": sha256_path(path), "committed": committed}


def canonical(record: dict) -> str:
    return json.dumps(record, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


def record_hash(record: dict) -> str:
    body = {k: v for k, v in record.items() if k != "recordSha256"}
    return hashlib.sha256(canonical(body).encode("utf-8")).hexdigest()


def summarize_cases(cases: list[dict]) -> dict[str, int]:
    counts = {s: 0 for s in STATUSES}
    for c in cases:
        counts[c["status"]] = counts.get(c["status"], 0) + 1
    return counts


def relative_paths(record: dict) -> dict:
    """Paths inside the repository are written relative to it: the records are public and the checkout's absolute
    path names the Mac's user (owner ruling 2026-11-15)."""
    text = json.dumps(record, ensure_ascii=False)
    root = str(ROOT)
    text = text.replace(root + "/", "").replace(root, ".")
    return json.loads(text)


def write_record(record: dict, directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    clean = relative_paths(record)
    record.clear()
    record.update(clean)
    record["summary"] = summarize_cases(record["cases"])
    record["recordSha256"] = record_hash(record)
    path = directory / "record.json"
    path.write_text(canonical(record), encoding="utf-8")
    (directory / "record.json.sha256").write_text(f"{record['recordSha256']}  record.json\n", encoding="utf-8")
    (directory / "record.md").write_text(render_markdown(record), encoding="utf-8")
    return path


def render_markdown(record: dict) -> str:
    t, app, s = record["target"], record["app"], record["signing"]
    lines = [f"# QA-011 device run {record['label']} {record['runId']}", ""]
    if not record["evidence"]:
        lines += [f"**{record['evidenceNote'].upper()}.** Nothing here is device evidence (Constitution X).", ""]
    lines += [
        f"- Target: {t.get('kind')} {t.get('name')} `{t.get('productType')}`, OS {t.get('osVersion')} "
        f"({t.get('osBuild')}), state {t.get('state')}",
        f"- App: `{app.get('bundleID')}` {app.get('version')} ({app.get('build')}), {app.get('configuration')}, "
        f"commit `{app.get('commit')}`{' (dirty tree)' if app.get('dirty') else ''}",
        f"- Signing: {s.get('identity') or s.get('note') or 'not signed'}; team {s.get('team') or '-'}"
        f"{'; ad hoc' if s.get('adhoc') else ''}",
        f"- Host: {record['host'].get('xcode')}, macOS {record['host'].get('macOS')}",
        f"- Started {record['startedAt']}, finished {record['finishedAt']}"
        + (f"; stopped: {record['stopReason']}" if record.get("stopReason") else ""),
        f"- Summary: " + ", ".join(f"{k} {v}" for k, v in record["summary"].items() if v),
        f"- Record SHA-256: `{record['recordSha256']}`", "",
        "| Case | Status | Seconds | Closes | Detail |", "|---|---|---|---|---|"]
    for c in record["cases"]:
        closes = ", ".join(c.get("closes", []) + [f"part of {x}" for x in c.get("partOf", [])])
        detail = (c.get("detail") or "").replace("|", "/").replace("\n", " ")[:300]
        lines.append(f"| `{c['id']}` | {c['status']} | {c.get('durationSeconds', 0):.1f} | {closes} | {detail} |")
    lines += ["", "## Artifacts", "", "| Case | Path | Bytes | SHA-256 | Committed |", "|---|---|---|---|---|"]
    for c in record["cases"]:
        for a in c.get("artifacts", []):
            lines.append(f"| `{c['id']}` | `{a['path']}` | {a['bytes']} | `{a['sha256']}` | "
                         f"{'yes' if a['committed'] else 'no'} |")
    return "\n".join(lines) + "\n"


def verify_record(path: Path) -> list[str]:
    """Problems with a record: a wrong record hash, or a committed artifact missing or changed. Artifacts kept
    outside the repository (xcresults) are not checked: they are local working files, not committed evidence."""
    record = json.loads(path.read_text(encoding="utf-8"))
    problems = []
    if record.get("recordSha256") != record_hash(record):
        problems.append("record hash does not match its content")
    sidecar = path.with_name("record.json.sha256")
    if sidecar.exists() and sidecar.read_text(encoding="utf-8").split()[0] != record.get("recordSha256"):
        problems.append("record.json.sha256 does not match the record")
    for c in record.get("cases", []):
        for a in c.get("artifacts", []):
            p = Path(a["path"]) if Path(a["path"]).is_absolute() else ROOT / a["path"]
            if not p.exists():
                if a.get("committed"):
                    problems.append(f"missing artifact {a['path']}")
                continue
            if sha256_path(p) != a["sha256"] and a.get("committed"):
                problems.append(f"artifact changed: {a['path']}")
            # An uncommitted artifact (an xcresult under Build/) is not evidence that can be checked later: Xcode
            # keeps rewriting a result bundle's database after the run, so its folder hash drifts (D1, 2026-11-15).
    return problems


# MARK: - Target, app and signing facts

def device_entry(listing: dict, label: str) -> dict | None:
    model = rdt.DEVICES[label]
    for device in listing.get("result", {}).get("devices", []):
        hw = device.get("hardwareProperties", {})
        if hw.get("productType") == model and hw.get("reality", "physical") == "physical":
            return device
    return None


def device_facts(device: dict | None) -> dict:
    if not device:
        return {"kind": "device", "state": "not listed"}
    hw, dp = device.get("hardwareProperties", {}), device.get("deviceProperties", {})
    state = device.get("connectionProperties", {}).get("tunnelState", "unknown")
    return {"kind": "device", "identifier": device.get("identifier"), "udid": hw.get("udid"),
            "name": dp.get("name"), "productType": hw.get("productType"), "osVersion": dp.get("osVersionNumber"),
            "osBuild": dp.get("osBuildUpdate"), "state": state}


def simulator_facts(devices_json: dict, runtimes_json: dict, udid: str) -> dict:
    builds = {r.get("identifier"): r for r in runtimes_json.get("runtimes", [])}
    for runtime, devices in devices_json.get("devices", {}).items():
        for d in devices:
            if d.get("udid") == udid:
                r = builds.get(runtime, {})
                return {"kind": "simulator", "identifier": udid, "udid": udid, "name": d.get("name"),
                        "productType": d.get("deviceTypeIdentifier", "").rsplit(".", 1)[-1],
                        "osVersion": r.get("version"), "osBuild": r.get("buildversion"),
                        "state": d.get("state", "unknown").lower()}
    return {"kind": "simulator", "identifier": udid, "udid": udid, "state": "not listed"}


def parse_codesign(text: str) -> dict:
    """`codesign -dv --verbose=4` output (stderr) → signed, identity (first Authority), team, adhoc."""
    if "not signed at all" in text:
        return {"signed": False, "identity": None, "team": None, "adhoc": False, "raw": ["code object is not signed at all"]}
    authorities = re.findall(r"^Authority=(.+)$", text, re.M)
    team = re.search(r"^TeamIdentifier=(.+)$", text, re.M)
    adhoc = bool(re.search(r"^Signature=adhoc$", text, re.M))
    team_value = team.group(1).strip() if team else None
    if team_value == "not set":
        team_value = None
    raw = [line for line in text.splitlines() if line.startswith(("Authority=", "TeamIdentifier=", "Signature="))]
    return redact_signing({"signed": bool(authorities) or adhoc, "identity": authorities[0] if authorities else None,
                           "team": team_value, "adhoc": adhoc, "raw": raw})


# Owner ruling 2026-11-15: records are public, so a signing identity keeps only the certificate type and the team ID.
# The certificate's holder name and personal certificate ID ("Apple Development: NAME (ABCDE12345)") are dropped.
REDACTION_NOTE = "certificate holder name and certificate ID withheld; team ID kept (owner ruling 2026-11-15)"


def redact_identity(value: str | None) -> str | None:
    """'Apple Development: NAME (ID)' → 'Apple Development'; Apple's own CA names are kept."""
    if value is None:
        return None
    kind, sep, _ = value.partition(":")
    return kind.strip() if sep else value


def redact_signing(signing: dict) -> dict:
    out = dict(signing)
    out["identity"] = redact_identity(signing.get("identity"))
    raw = []
    for line in signing.get("raw", []):
        if line.startswith("Authority="):
            raw.append("Authority=" + redact_identity(line[len("Authority="):]))
        else:
            raw.append(line)
    out["raw"] = raw
    if out["identity"] != signing.get("identity"):
        out["redaction"] = REDACTION_NOTE
    return out


def redact_record_file(path: Path) -> bool:
    """Rewrite a committed-to-be record with its signing identity redacted; a new record hash. True if changed."""
    record = json.loads(path.read_text(encoding="utf-8"))
    before = canonical(record)
    record["signing"] = redact_signing(record.get("signing") or {})
    record = relative_paths(record)
    if canonical(record) == before:
        return False
    write_record(record, path.parent)
    return True


def capture(cmd: list[str], cwd: Path | None = None, timeout: float | None = None) -> subprocess.CompletedProcess:
    """Run for facts only; a missing tool (xcodebuild, codesign and xcrun on Linux CI) gives an empty result, and a
    command past `timeout` exit status 124."""
    try:
        return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, check=False, timeout=timeout)
    except FileNotFoundError:
        return subprocess.CompletedProcess(cmd, 127, stdout="", stderr=f"{cmd[0]}: not found")
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 124, stdout="", stderr=f"{cmd[0]}: timed out after {timeout} s")


def app_facts(app: Path, configuration: str) -> dict:
    facts = {"bundleID": rdt.BUNDLE, "path": display_path(app), "configuration": configuration,
             "commit": capture(["git", "rev-parse", "HEAD"], ROOT).stdout.strip(),
             "dirty": bool(capture(["git", "status", "--porcelain", "--untracked-files=no"], ROOT).stdout.strip())}
    plist = app / "Info.plist"
    for key, field in (("CFBundleShortVersionString", "version"), ("CFBundleVersion", "build"),
                       ("CFBundleIdentifier", "bundleID")):
        out = capture(["plutil", "-extract", key, "raw", "-o", "-", str(plist)]) if plist.exists() else None
        if out and out.returncode == 0:
            facts[field] = out.stdout.strip()
        elif field != "bundleID":
            facts[field] = None
    return facts


def signing_facts(app: Path) -> dict:
    if not app.exists():
        return {"signed": False, "identity": None, "team": None, "adhoc": False, "raw": [],
                "note": f"app not found: {display_path(app)}"}
    out = capture(["codesign", "-dv", "--verbose=4", str(app)])
    return parse_codesign(out.stderr + out.stdout)


def host_facts() -> dict:
    xcode = capture(["xcodebuild", "-version"]).stdout.strip().replace("\n", " ")
    return {"xcode": xcode or None, "macOS": platform.mac_ver()[0] or None}


# MARK: - Running cases

class MatrixTarget(rdt.Target):
    """run_device_tests' Target, with pulled reports going next to the run record."""

    def __init__(self, label: str, identifier: str, simulator: bool, out_dir: Path, udid: str | None):
        super().__init__(label, identifier, simulator)
        self._out_dir, self.udid = out_dir, udid

    @property
    def out_dir(self) -> Path:
        return self._out_dir

    @property
    def destination(self) -> str:
        return f"id={self.identifier}" if self.simulator else f"platform=iOS,id={self.udid or '<UDID>'}"


class Blocked(Exception):
    """The device stayed locked past --locked-wait."""


class NoDeviceHost(Exception):
    """A package suite with no app-hosted twin in DeviceTests.yml: it cannot run on a device yet."""


# Xcode cannot run a package's own test target on a device ("Tool-hosted testing is unavailable on device
# destinations"; D1, 2026-11-15). On a device, package suites run from DeviceTests.yml: the same sources compiled
# into bundles hosted in the signed app. A package test bundle without a twin there cannot run on a device yet.
DEVICE_TEST_SPEC = ROOT / "DeviceTests.yml"
DEVICE_TEST_PROJECT = ROOT / "ProjectM-DeviceTests.xcodeproj"
DEVICE_TEST_SCHEME = "DeviceTests"
DEVICE_TEST_BUNDLES = {
    "CompositorTests": "CompositorDeviceTests",
    "ProceduralMaterialsTests": "MaterialsDeviceTests",
    "GeneratorGraphTests": "GeneratorGraphDeviceTests",
    "FrameRecordingTests": "RecordingDeviceTests",
    "ParameterExpressionTests": "ExpressionDeviceTests",
    "RenderGoldensTests": "RenderGoldensDeviceTests",
    "ANGLERenderingTests": "ANGLEDeviceTests",
}


PACKAGE_DEVICE_BUNDLES = {"RenderGoldens": ["RenderGoldensDeviceTests"], "ParameterGraph": ["ExpressionDeviceTests"]}


def device_only_testing(only: list[str], package: str | None = None) -> list[str] | None:
    """The device-hosted `-only-testing` ids, or None when a bundle has no device host. A case without `only` runs
    its package's bundles, never the whole scheme (D1, 2026-11-15: an unfiltered case ran every bundle)."""
    if not only:
        return PACKAGE_DEVICE_BUNDLES.get(package or "")
    out = []
    for o in only:
        bundle, _, rest = o.partition("/")
        if bundle not in DEVICE_TEST_BUNDLES:
            return None
        out.append(DEVICE_TEST_BUNDLES[bundle] + ("/" + rest if rest else ""))
    return out


def xctest_command(c: dict, target: MatrixTarget, derived: Path, bundle: Path) -> tuple[list[str], Path]:
    only = list(c.get("only", []))
    hosted = not c.get("app") and not target.simulator
    if c.get("app"):
        cmd, cwd = ["xcodebuild", "test", "-project", str(rdt.PROJECT), "-scheme", rdt.SCHEME], ROOT
    elif hosted:
        mapped = device_only_testing(only, c.get("package"))
        if mapped is None:
            raise NoDeviceHost(f"{', '.join(only)}: no app-hosted device bundle (DeviceTests.yml)")
        only = mapped
        cmd, cwd = ["xcodebuild", "test", "-project", str(DEVICE_TEST_PROJECT), "-scheme", DEVICE_TEST_SCHEME], ROOT
    else:
        cmd, cwd = ["xcodebuild", "test", "-scheme", c["package"]], ROOT / "Packages" / c["package"]
    cmd += ["-destination", target.destination,
            "-derivedDataPath", str(derived / ("device-tests" if hosted else (c.get("package") or "app"))),
            "-resultBundlePath", str(bundle), "-test-timeouts-enabled", "YES",
            "-default-test-execution-time-allowance", str(c["timeoutSeconds"])]
    if c.get("configuration") or hosted:
        cmd += ["-configuration", c.get("configuration") or "Debug", "ENABLE_TESTABILITY=YES"]
    for o in only:
        cmd.append(f"-only-testing:{o}")
    if target.simulator:
        cmd.append("CODE_SIGNING_ALLOWED=NO")
    else:
        cmd.append("-allowProvisioningUpdates")
        if not c.get("app") and not hosted:
            cmd += ["-xcconfig", str(SIGNING_XCCONFIG)]   # the owner's team via the include-only file
    return cmd, cwd


def test_counts(log: str) -> str:
    found = re.findall(r"Executed (\d+) tests?, with (?:\d+ tests? skipped and )?(\d+) failures?(?: \((\d+) unexpected\))?", log)
    skipped = len(re.findall(r"Test Case .* skipped", log))
    if not found:
        return "no test summary in the log"
    n, f, _ = max(found, key=lambda t: int(t[0]))   # the whole run's total, not the last sub-suite (D1, 2026-11-15)
    return f"{n} tests, {f} failures, {skipped} skipped"


def is_locked(text: str) -> bool:
    return bool(LOCK_RE.search(text)) and "Executed " not in text


def dig(data, path: str):
    """data["a"]["b"] for "a.b"; None when any part is missing."""
    for part in path.split("."):
        if not isinstance(data, dict) or part not in data:
            return None
        data = data[part]
    return data


def flashcost_verdict(report: dict, limit_ms: float) -> dict:
    """FX-019-T22: RendererLab's flashcost summary against the 2 ms per frame budget (FX-019-S6).

    The statistic, newest first, used when every preset has it (FX-019 Clarifications, 2026-11-24):
    - `passCostMedianMs`: the pass's own cost on the frame it processes, GPU time from a timer query plus CPU encoding
      time, per frame; every preset's median at most the limit.
    - `passMedianMs` (first paired version, D1 run 20261124T191740Z): glFinish -> pass -> glFinish on the wall clock,
      which also counts a submit-and-wait round trip the app never pays; still judged as written, for old reports.
    - `costMs`: on minus off of separate frames (T104), whose per-preset values moved by up to 2 ms between two runs of
      identical code; decides only for reports without paired times. It stays in the detail either way."""
    summary = report.get("summary") or {}
    results = report.get("flashCost") or []
    costs = [r.get("costMs", 0) for r in results]
    key = "costMs"
    for candidate in ("passCostMedianMs", "passMedianMs"):
        if results and all(r.get(candidate) is not None for r in results):
            key = candidate
            break
    paired = key != "costMs"
    over = [r["id"] for r in results if r.get(key, 0) > limit_ms]
    n = int(summary.get("presets", len(costs)))
    worst, median = summary.get("costMsMax", max(costs, default=0)), summary.get("costMsMedian", 0)
    label = {"passCostMedianMs": "pass", "passMedianMs": "pass wall"}.get(key, "")

    def spread(r: dict) -> str:
        """2026-11-23: what a reader needs to tell a cost from noise (ABBA round costs, dimmed share, frame-time IQR)."""
        parts = [f"{label} {r[key]:.2f} ms" if paired else f"{r.get('costMs', 0):.2f} ms"]
        if key == "passCostMedianMs":
            parts.append(f"GPU {r.get('passGpuMedianMs') or 0:.2f}, CPU {r.get('passCpuMedianMs') or 0:.2f}")
        if paired:
            parts.append(f"on - off {r.get('costMs', 0):.2f} ms")
        rounds = r.get("roundCostsMs") or []
        if rounds:
            parts.append(f"rounds {min(rounds):.2f}-{max(rounds):.2f}")
        if r.get("dimmedFraction") is not None:
            parts.append(f"dimmed {r['dimmedFraction']:.0%}")
        if r.get("onIqrMs") is not None and r.get("offIqrMs") is not None:
            parts.append(f"IQR off {r['offIqrMs']:.2f} on {r['onIqrMs']:.2f}")
        return ", ".join(parts)

    def middle(values: list[float]) -> float:
        values = sorted(values)
        return values[len(values) // 2] if values else 0.0

    over_detail = [f"{r['id']} ({spread(r)})" for r in results if r.get(key, 0) > limit_ms]
    result = {"presets": n, "medianMs": median, "maxMs": worst, "over": over, "statistic": key}
    if paired:
        passes = sorted(r[key] for r in results)
        pass_median, pass_worst = passes[len(passes) // 2], passes[-1]
        if key == "passCostMedianMs":
            gpu = middle([r["passGpuMedianMs"] for r in results if r.get("passGpuMedianMs") is not None])
            cpu = middle([r["passCpuMedianMs"] for r in results if r.get("passCpuMedianMs") is not None])
            trip = middle([r["roundTripMedianMs"] for r in results if r.get("roundTripMedianMs") is not None])
            detail = (f"{n} presets, pass (GPU timer + CPU encoding) median {pass_median:.2f} ms, max {pass_worst:.2f} ms "
                      f"per frame (limit {limit_ms} ms; medians GPU {gpu:.2f}, CPU {cpu:.2f}, excluded round trip "
                      f"{trip:.2f} ms); on - off of separate frames median {median:.2f}, max {worst:.2f} ms")
            result.update(gpuMedianMs=gpu, cpuMedianMs=cpu, roundTripMedianMs=trip)
        else:
            detail = (f"{n} presets, pass alone median {pass_median:.2f} ms, max {pass_worst:.2f} ms per frame (limit "
                      f"{limit_ms} ms); on - off of separate frames median {median:.2f}, max {worst:.2f} ms")
        decisive = pass_worst
        result.update(passMedianMs=pass_median, passMaxMs=pass_worst)
    else:
        detail = f"{n} presets, median {median:.2f} ms, max {worst:.2f} ms per frame (limit {limit_ms} ms)"
        decisive = worst
    detail += ((f"; over: {', '.join(over_detail[:5])}" if over else "")
               + (f"; thermal {', '.join(report['thermalStates'])}" if report.get("thermalStates") else ""))
    result.update({"pass": n > 0 and decisive <= limit_ms, "detail": detail if n else "no presets measured"})
    return result


def apply_stop_policy(verdict: dict, runs: list[dict]) -> dict:
    """A recording that had to be stopped counts only when its window was whole and its data readable: xctrace said
    the app had exited (the app's run, and so the recording window, had ended) and the stopped trace was still saved
    whole and exported (Clarification FX-019/PERF-004, 2026-11-23). Anything else fails, whatever was salvaged (the
    perf011 trace stopped mid-save exported nothing). How long each save took after the app exited is named too."""
    notes = [f"{r['name']}: saved {r['saveSeconds']:.0f} s after the app exited" for r in runs
             if not r.get("stopped") and isinstance(r.get("saveSeconds"), (int, float))]
    stopped = [r for r in runs if r.get("stopped")]
    unusable = [r for r in stopped if not (r.get("appExited") and r.get("traceSaved") and r.get("tables"))]
    if unusable:
        verdict["pass"] = False
        verdict["detail"] = ("xctrace did not end by itself and was stopped ("
                             + "; ".join(f"{r['name']}: {r['stopped']}" for r in unusable) + "); " + verdict["detail"])
    elif stopped:
        verdict["detail"] = ("stopped after the app had exited, trace saved and exported ("
                             + "; ".join(f"{r['name']}: {r['stopped']}" for r in stopped) + "); " + verdict["detail"])
    if notes:
        verdict["detail"] = verdict["detail"] + " (" + "; ".join(notes) + ")"
    return verdict


def perf004_ready(events: list[tuple[float, str]], report: dict | None) -> float | None:
    """Trace seconds at which perf004's playback start had returned, for traces without a "QA-011 ready" marker: the
    app times its marks from that moment (`markSeconds.rotate`), so "QA-011 rotate" in the trace minus that offset is
    it (D1 20261123T200159Z: 18.653 - 10.001 = 8.652 s, 5.0 s after "QA-011 start")."""
    rotate = xt.marker_times(events).get("rotate")
    offset = ((report or {}).get("markSeconds") or {}).get("rotate")
    if rotate is None or not isinstance(offset, (int, float)):
        return None
    return rotate - offset


def verdict_perf004(runs: list[dict]) -> dict:
    run = runs[0] if runs else {}
    rows = (run.get("tables") or {}).get(xt.SIGNPOST_SCHEMA)
    if rows is None:
        return {"pass": False, "detail": f"no {xt.SIGNPOST_SCHEMA} table exported (trace saved: {run.get('traceSaved')})"}
    events = xt.signpost_events(rows)
    verdict = xt.perf004_verdict(events, ready=perf004_ready(events, run.get("report")))
    if run.get("report") and not run["report"].get("rotationRequested"):
        verdict["pass"], verdict["detail"] = False, "the app could not request the rotation; " + verdict["detail"]
    return verdict


def verdict_perf011(runs: list[dict]) -> dict:
    run = runs[0] if runs else {}
    if not run.get("report"):
        return {"pass": False, "detail": "no perf011 report pulled"}
    tables = run.get("tables") or {}
    events = xt.signpost_events(tables[xt.SIGNPOST_SCHEMA]) if xt.SIGNPOST_SCHEMA in tables else None
    verdict = xt.perf011_verdict(run["report"], tables.get(xt.GPU_SCHEMA), events)
    if xt.GPU_SCHEMA not in tables:
        verdict["detail"] += f"; GPU intervals not checked (no {xt.GPU_SCHEMA} table exported)"
    return verdict


def verdict_perf008(runs: list[dict]) -> dict:
    """PERF-008-T16: both profiles measured; Battery saver at its 30 fps cap and below Standard; per-minute frame
    time (app report) and energy (Power Profiler tables, best effort) side by side."""
    by = {}
    for run in runs:
        report = run.get("report") or {}
        fps = sorted(report.get("fps") or [])
        power = {schema: xt.per_minute(rows) for schema, rows in (run.get("tables") or {}).items()
                 if xt.POWER_SCHEMA_RE.search(schema)}
        by[report.get("profile", run["name"])] = {"fpsMedian": fps[len(fps) // 2] if fps else 0,
                                                  "perMinute": report.get("perMinute", []), "energy": power,
                                                  "traceSaved": run.get("traceSaved")}
    std, saver = by.get("standard"), by.get("batterySaver")
    if not std or not saver:
        return {"pass": False, "detail": f"profiles measured: {sorted(by)}", "profiles": by}
    ok = saver["fpsMedian"] <= 31 and saver["fpsMedian"] < std["fpsMedian"]
    energy = "energy tables: " + (", ".join(sorted({k for v in by.values() for k in v["energy"]})) or "none exported")
    return {"pass": ok, "profiles": by, "detail": f"Standard {std['fpsMedian']:.1f} fps, Battery saver "
            f"{saver['fpsMedian']:.1f} fps (cap 30); {energy}"}


XCTRACE_VERDICTS = {"perf004": verdict_perf004, "perf011": verdict_perf011, "perf008": verdict_perf008}


class Runner:
    def __init__(self, target: MatrixTarget, work: Path, locked_wait: float, perf012: list[Path],
                 dry_run: bool):
        self.target, self.work, self.locked_wait, self.perf012, self.dry_run = target, work, locked_wait, perf012, dry_run
        self.derived = work / "derived-data"
        self.fresh_install = False      # set when this run reinstalled the app (its permission answers are gone)
        self.rendererlab_app: Path | None = None
        # --build rebuilds RendererLab too (an incremental build): built only when missing, it kept measuring the code of
        # its first build (D1, 2026-11-23: the FX-019 lookup-table fix was measured with a 14:14 RendererLab).
        self.rebuild_rendererlab = False

    def run_case(self, c: dict) -> dict:
        result = {"id": c["id"], "kind": c["kind"], "title": c["title"], "closes": c["closes"],
                  "partOf": c.get("partOf", []), "status": "not-run", "commands": [], "artifacts": [],
                  "detail": "", "durationSeconds": 0.0}
        start = time.monotonic()
        try:
            getattr(self, "case_" + c["kind"])(c, result)
        except Blocked as e:
            result["status"], result["detail"] = "blocked", str(e)
        except subprocess.TimeoutExpired:
            result["status"], result["detail"] = "timeout", f"over the {c['timeoutSeconds']} s limit"
        except SystemExit as e:   # run_device_tests exits on a launch that never succeeded
            text = str(e)
            if "Locked" in text:
                result["status"], result["detail"] = "blocked", self.locked_message()
            else:
                result["status"], result["detail"] = "error", text[-600:]
        except Exception as e:  # noqa: BLE001 - recorded, and the next case runs
            result["status"], result["detail"] = "error", f"{type(e).__name__}: {e}"
        result["durationSeconds"] = round(time.monotonic() - start, 1)
        return result

    def locked_message(self) -> str:
        return (f"{self.target.label} stayed locked for {self.locked_wait:.0f} s: unlock it and set Auto-Lock to "
                f"Never, then rerun with --only for the remaining cases")

    def add(self, result: dict, path: Path | None, committed: bool) -> None:
        if path and path.exists() and not self.dry_run:
            result["artifacts"].append(artifact(path, committed))

    # Each case_* fills result["status"], ["detail"], ["artifacts"]; commands are printed by rdt.run.

    def case_autorun(self, c: dict, result: dict) -> None:
        if c.get("prompts") and self.fresh_install and not self.target.simulator:
            result["status"] = "not-run"
            result["detail"] = (f"raises the {c['prompts']} prompt after this run's fresh install (owner rule 14): run the "
                                f"prompt-flow batch first, then --only {c['id']} --no-install")
            print(f"!! {c['id']}: {result['detail']}", flush=True)
            return
        env = dict(c.get("env", {}))
        result["commands"].append(["PROJECTM_AUTORUN=" + c["mode"]] + [f"{k}={v}" for k, v in env.items()]
                                  + ["launch", rdt.BUNDLE])
        if c.get("prompts") and self.target.simulator:   # a rehearsal grants it
            rdt.run(["xcrun", "simctl", "privacy", self.target.identifier, "grant", c["prompts"], rdt.BUNDLE], check=False)
        if c.get("permission"):
            if self.target.simulator:   # a rehearsal grants it; on a device a person taps Allow once
                rdt.run(["xcrun", "simctl", "privacy", self.target.identifier, "grant", c["permission"], rdt.BUNDLE],
                        check=False)
            else:
                print(f">>> {self.target.label}: the fresh install asks for {c['permission']} access during this "
                      f"case; tap Allow on the device (one tap; the case waits up to {c['wait']} s)", flush=True)
        if self.target.simulator and not self.dry_run:
            self.sample_if_stalled(c)
        report = rdt.run_mode(self.target, c["mode"], c["prefix"], c["wait"], env or None)
        if self.dry_run:
            result["status"] = "skipped"
            return
        if not report:
            result["status"], result["detail"] = "fail", f"no {c['prefix']} report within {c['wait']} s"
            sample = self.work / "logs" / f"{c['id']}-sample.txt"
            if sample.exists():
                self.add(result, sample, False)
                result["detail"] += f"; main-thread sample in {display_path(sample)}"
            return
        self.add(result, report, report.stat().st_size <= COMMIT_LIMIT)
        data = json.loads(report.read_text())
        error = data.get("error") if isinstance(data, dict) else None
        missing = c.get("expect") and not error and dig(data, c["expect"]) is None
        result["status"] = "fail" if error or missing else "pass"
        result["detail"] = error or (f"report {report.name} has no {c['expect']}" if missing else f"report {report.name}")

    def sample_if_stalled(self, c: dict) -> None:
        """Simulator rehearsal: when no report has come after most of the wait, sample the app's threads with the Mac's
        `sample` (a simulator app is a Mac process), so a stall shows where the main thread waits."""
        out = self.work / "logs" / f"{c['id']}-sample.txt"
        out.parent.mkdir(parents=True, exist_ok=True)
        delay = max(30.0, c["wait"] * 0.8)

        def later() -> None:
            time.sleep(delay)
            pids = capture(["pgrep", "-f", f"{rdt.SCHEME}.app/{rdt.SCHEME}"]).stdout.split()
            if pids:
                capture(["sample", pids[0], "3", "-file", str(out)])

        threading.Thread(target=later, daemon=True).start()

    # MARK: RendererLab (FX-019-T22)

    def rendererlab_path(self) -> Path:
        sdk = "iphonesimulator" if self.target.simulator else "iphoneos"
        return self.rendererlab_app or RENDERERLAB_BUILD / f"Build/Products/Release-{sdk}/RendererLab.app"

    def rendererlab_build(self) -> list[str]:
        cmd = ["xcodebuild", "-project", str(RENDERERLAB_PROJECT), "-scheme", "RendererLab", "-configuration", "Release",
               "-derivedDataPath", str(RENDERERLAB_BUILD)]
        if self.target.simulator:
            return cmd + ["-destination", f"id={self.target.identifier}", "CODE_SIGNING_ALLOWED=NO", "build"]
        return cmd + ["-destination", "generic/platform=iOS", "-allowProvisioningUpdates", "build"]

    def case_rendererlab(self, c: dict, result: dict) -> None:
        t = self.target
        lab = MatrixTarget(t.label, t.identifier, t.simulator, t.out_dir, t.udid)
        lab.bundle, lab.app_name = RENDERERLAB_BUNDLE, "RendererLab"
        app = self.rendererlab_path()
        if not app.exists() or self.rebuild_rendererlab or self.dry_run:
            if not RENDERERLAB_PROJECT.exists():
                result["commands"].append(["xcodegen", "generate", "--spec", "RendererLab.yml"])
                rdt.run(["xcodegen", "generate", "--spec", str(ROOT / "RendererLab.yml")])
            build = self.rendererlab_build()
            result["commands"].append(build)
            rdt.run(build, timeout=3600)
        lab.install(app)
        env = {"RL_BACKEND": "angle", "RL_MODE": "flashcost"}
        result["commands"].append([f"{k}={v}" for k, v in env.items()] + ["launch", RENDERERLAB_BUNDLE])
        report = rdt.run_mode(lab, "flashcost", "RendererLab-angle-flashcost", c["wait"], env)
        if self.dry_run:
            result["status"] = "skipped"
            return
        if not report:
            result["status"], result["detail"] = "fail", f"no RendererLab flashcost report within {c['wait']} s"
            return
        self.add(result, report, report.stat().st_size <= COMMIT_LIMIT)
        verdict = flashcost_verdict(json.loads(report.read_text()), c["limitMs"])
        result["status"], result["detail"] = ("pass" if verdict["pass"] else "fail"), verdict["detail"]

    # MARK: Instruments (PERF-004-T16, PERF-008-T16, PERF-011-T21)

    def wait_for_launch(self, before: set[int], timeout: float = 180) -> float:
        """Seconds until a new process of the app appears on the device (xctrace's --launch), or -1 after `timeout`.

        D1, 2026-11-23: Metal System Trace took about 18 s from the command to the app's launch, so Settings, opened
        15 s after the command, came first; the app started in the background and was only brought to the front once
        ("not backgrounded and brought back"). The background steps are now timed from the app's own launch."""
        started = time.monotonic()
        while time.monotonic() - started < timeout:
            if set(self.target.app_pids()) - before:
                return time.monotonic() - started
            time.sleep(1)
        return -1

    def drive_background(self, at: list[float], before: set[int] | None = None) -> threading.Thread:
        """PERF-011: the Mac sends the app to the background by opening Settings at at[0] s, and brings it back at
        at[1] s (a launch of a running app activates it; no --terminate-existing). On a device both times count from
        the moment the app's process appears (`wait_for_launch`); without it, from now."""
        t = self.target
        if t.simulator:
            away = ["xcrun", "simctl", "launch", t.identifier, "com.apple.Preferences"]
            back = ["xcrun", "simctl", "launch", t.identifier, rdt.BUNDLE]
        else:
            away = ["xcrun", "devicectl", "device", "process", "launch", "--device", t.identifier, "com.apple.Preferences"]
            back = ["xcrun", "devicectl", "device", "process", "launch", "--device", t.identifier, rdt.BUNDLE]

        def act() -> None:
            if before is not None and not t.simulator and not self.dry_run:
                waited = self.wait_for_launch(before)
                print(f"   the app launched {waited:.0f} s after the recording command" if waited >= 0 else
                      "   the app's process never appeared; sending it away on the fixed schedule", flush=True)
            time.sleep(0 if self.dry_run else at[0])
            rdt.run(away, check=False, capture=True)
            time.sleep(0 if self.dry_run else at[1] - at[0])
            rdt.run(back, check=False, capture=True)

        thread = threading.Thread(target=act, daemon=True)
        thread.start()
        return thread

    def case_xctrace(self, c: dict, result: dict) -> None:
        t = self.target
        folder = self.work / "traces" / c["id"]
        runs: list[dict] = []
        for run in c["runs"]:
            trace = folder / f"{run['name']}.trace"
            if not self.dry_run:
                folder.mkdir(parents=True, exist_ok=True)
                if trace.exists():
                    shutil.rmtree(trace)
            env = {"PROJECTM_AUTORUN": run["mode"], **run.get("env", {})}
            cmd = xt.record_command(t.identifier if t.simulator else (t.udid or "<UDID>"), run["template"],
                                    run["seconds"], trace, rdt.BUNDLE, env=env, instruments=run.get("instruments", []))
            result["commands"].append(cmd)
            before = set(t.container_files("Documents"))
            pids = set(t.app_pids())
            driver = self.drive_background(run["background"], pids) if run.get("background") else None
            log = self.work / "logs" / f"{c['id']}-{run['name']}.log"
            if self.dry_run:
                rdt.run(cmd, check=False, capture=True)
                if driver:
                    driver.join(timeout=5)
                continue
            # Never a short timeout (saving a trace takes minutes, and a killed save leaves it unreadable), but never
            # unwatched: `xt.record` stops xctrace with SIGINT only after the measured save allowance or a hard limit.
            # No second attempt: on D1 the save itself takes 3-5 minutes, and two attempts would pass the 10-minute
            # budget for one check (2026-11-24; the 2026-11-23 retry only repeated a stop that destroyed the trace).
            print("$ " + " ".join(shlex.quote(part) for part in cmd), flush=True)
            proc = xt.record(cmd, trace, log, run["seconds"])
            if driver:
                driver.join(timeout=5)
            text = proc["text"]
            self.add(result, log, False)
            if proc["exit"] != 0 and not t.simulator and is_locked(text):
                raise Blocked(self.locked_message())
            if proc["stopped"]:
                print(f"!! {c['id']} {run['name']}: xctrace {proc['stopped']}; stopped it", flush=True)
            elif proc.get("saveSeconds") is not None:
                print(f"   xctrace saved {proc['saveSeconds']:.0f} s after the app exited", flush=True)
            name = t.wait_for_report(f"automation-{run['mode']}", before, 120)
            report = None
            if name:
                dest = t.out_dir / f"{c['id']}-{name}"
                t.pull(f"Documents/{name}", dest)
                self.add(result, dest, dest.stat().st_size <= COMMIT_LIMIT)
                report = json.loads(dest.read_text())
            # Exported whenever the bundle was saved whole, also after a stop (`trace_complete`: a directory alone is
            # not a saved trace; D1 2026-11-23 said "trace saved: True" for a bundle holding only the raw .atrc).
            tables = self.export_tables(trace, run, folder) if proc.get("complete", trace.exists()) else {}
            runs.append({"name": run["name"], "exit": proc["exit"], "report": report, "tables": tables,
                         "traceSaved": proc.get("complete", trace.exists()), "stopped": proc["stopped"],
                         "appExited": proc.get("appExited", False), "recordSeconds": proc["seconds"],
                         "saveSeconds": proc.get("saveSeconds")})
        if self.dry_run:
            result["status"] = "skipped"
            return
        verdict = XCTRACE_VERDICTS[c["verdict"]](runs)
        apply_stop_policy(verdict, runs)
        out = t.out_dir / f"{c['id']}-verdict.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(verdict, indent=2, sort_keys=True, default=str) + "\n")
        self.add(result, out, True)
        result["status"], result["detail"] = ("pass" if verdict["pass"] else "fail"), verdict["detail"]

    def export_tables(self, trace: Path, run: dict, folder: Path) -> dict[str, list]:
        """The run's tables as parsed rows (schema -> rows); the exported XML stays next to the trace."""
        # A trace whose save was stopped can make `export` hang as well; each export gets 10 minutes.
        toc = capture(xt.toc_command(trace), timeout=600)
        if toc.returncode != 0:
            return {}
        schemas = [e["schema"] for e in xt.parse_toc(toc.stdout) if e["run"] == 1]
        wanted = [s for s in schemas
                  if s in run.get("tables", []) or (run.get("powerTables") and xt.POWER_SCHEMA_RE.search(s))]
        out = {}
        for schema in wanted:
            xml = folder / f"{run['name']}-{schema}.xml"
            if capture(xt.export_command(trace, schema, xml), timeout=600).returncode == 0 and xml.exists():
                out[schema] = xt.parse_table(xml.read_text(errors="replace"))
        return out

    def case_launches(self, c: dict, result: dict) -> None:
        dest = rdt.launches(self.target, c["mode"], c["repeat"])
        if self.dry_run:
            result["status"] = "skipped"
            return
        samples = json.loads(dest.read_text()) if dest.exists() else []
        self.add(result, dest, True)
        result["status"] = "pass" if samples else "fail"
        result["detail"] = f"{len(samples)} launches recorded" if samples else "no samples"

    def case_warmstart(self, c: dict, result: dict) -> None:
        t = self.target
        t.launch("perf009")                       # a fresh install only acknowledges the notice
        time.sleep(0 if self.dry_run else 8)
        for _ in range(c["repeat"]):
            for extra in ({"PROJECTM_WARMCACHE": "cold"}, None):
                t.launch("perf009", extra)
                time.sleep(0 if self.dry_run else 6)
        dest = t.out_dir / "perf009.json"
        t.pull("Documents/perf009.json", dest)
        if self.dry_run:
            result["status"] = "skipped"
            return
        if not dest.exists():
            result["status"], result["detail"] = "fail", "perf009.json not pulled"
            return
        summary = rdt.warmstart_summary(json.loads(dest.read_text()), t.simulator)
        out = t.out_dir / "perf009-summary.json"
        out.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
        self.add(result, dest, True)
        self.add(result, out, True)
        ok = summary["cold"]["launches"] > 0 and summary["warm"]["launches"] > 0
        result["status"] = "pass" if ok else "fail"
        result["detail"] = (f"cold {summary['cold']['launches']} launches, library ready "
                            f"{summary['cold']['libraryReadyMs']} ms; warm {summary['warm']['launches']}, "
                            f"{summary['warm']['libraryReadyMs']} ms")

    def case_thresholds(self, c: dict, result: dict) -> None:
        t = self.target
        result["commands"].append(["check_performance_thresholds", str(t.out_dir)] + [str(p) for p in self.perf012])
        verdict = rdt.judge_thresholds(t.out_dir, label=t.label, simulator=t.simulator, extra=self.perf012,
                                       write=not self.dry_run)
        if self.dry_run:
            result["status"] = "skipped"
            return
        self.add(result, t.out_dir / "performance-verdict.json", True)
        code = cpt.exit_code(verdict)
        result["status"] = {0: "pass", 1: "fail"}.get(code, "error")
        result["detail"] = f"QA-010 overall {verdict.get('overall')}" + (
            f": {verdict.get('error')}" if verdict.get("error") else "")

    def case_xctest(self, c: dict, result: dict) -> None:
        bundle = self.work / "xcresult" / f"{c['id']}.xcresult"
        log = self.work / "logs" / f"{c['id']}.log"
        if not self.dry_run:
            bundle.parent.mkdir(parents=True, exist_ok=True)
            log.parent.mkdir(parents=True, exist_ok=True)
            if bundle.exists():
                shutil.rmtree(bundle)
        try:
            cmd, cwd = xctest_command(c, self.target, self.derived, bundle)
        except NoDeviceHost as e:
            result["status"], result["detail"] = "not-run", str(e)
            print(f"!! {c['id']}: {e}", flush=True)
            return
        if cwd == ROOT and DEVICE_TEST_PROJECT.name in " ".join(cmd) and not DEVICE_TEST_PROJECT.exists() \
                and not self.dry_run:
            subprocess.run(["xcodegen", "generate", "--spec", str(DEVICE_TEST_SPEC)], cwd=ROOT, check=True,
                           capture_output=True)
        env = {f"TEST_RUNNER_{k}": v for k, v in c.get("env", {}).items()}
        result["commands"].append([f"(cd {display_path(cwd)})"] + [f"{k}={v}" for k, v in env.items()] + cmd)
        deadline = time.monotonic() + self.locked_wait
        while True:
            print(f"$ (cd {display_path(cwd)}) " + " ".join(f"{k}={v}" for k, v in env.items()) + " "
                  + " ".join(cmd), flush=True)
            if self.dry_run:
                result["status"] = "skipped"
                return
            proc = subprocess.run(cmd, cwd=cwd, env={**os.environ, **env}, text=True, capture_output=True,
                                  timeout=c["timeoutSeconds"] + 900)   # the limit covers the test run; + build time
            text = proc.stdout + proc.stderr
            log.write_text(text)
            if proc.returncode != 0 and not self.target.simulator and is_locked(text):
                if time.monotonic() > deadline:
                    raise Blocked(self.locked_message())
                print(f"!! {self.target.label} is locked: unlock it (and set Auto-Lock to Never); retrying in 15 s",
                      flush=True)
                time.sleep(15)
                if bundle.exists():
                    shutil.rmtree(bundle)
                continue
            break
        self.add(result, log, False)
        self.add(result, bundle, False)
        if c.get("importGoldens"):   # QA-003-T17: the device goldens go into the package, not into the record
            self.import_goldens(bundle, c, result)
        else:
            for exported in self.export_attachments(bundle, c["id"]):
                self.add(result, exported, True)
        bench = [line for line in text.splitlines() if re.search(r"(?i)\b(bench|gpu time|QA-006 qa006)\b", line)
                 and "Test Case" not in line][:6]
        result["status"] = "pass" if proc.returncode == 0 else "fail"
        result["detail"] = test_counts(text) + (f"; exit {proc.returncode}" if proc.returncode else "") + (
            "; " + " / ".join(x.strip()[:160] for x in bench) if bench else "") + result["detail"]

    def import_goldens(self, bundle: Path, c: dict, result: dict) -> None:
        out = self.work / "attachments" / c["id"]
        exported = bundle.exists() and capture(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                                                "--output-path", str(out)]).returncode == 0
        captures = idg.read_captures(out) if exported else []
        if not captures:
            result["detail"] += "; no device-golden attachments exported"
            return
        golden_class, manifest, files = idg.build(captures)
        folder = idg.write(golden_class, manifest, files, idg.DEST)
        result["detail"] += f"; {len(files)} device goldens written to {display_path(folder)}"
        print(f"device goldens: {display_path(folder)} ({len(files)} files); add them to the repository, rebuild the "
              f"device tests and rerun xctest-goldens", flush=True)

    def export_attachments(self, bundle: Path, case_id: str) -> list[Path]:
        """JSON attachments (for example the QA-006 soak report) copied next to the record."""
        if not bundle.exists():
            return []
        out = self.work / "attachments" / case_id
        proc = capture(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                        "--output-path", str(out)])
        if proc.returncode != 0 or not out.exists():
            return []
        copied = []
        for p in sorted(out.rglob("*.json")):
            if p.name == "manifest.json" or p.stat().st_size > COMMIT_LIMIT:
                continue
            dest = self.target.out_dir / f"{case_id}-{p.name}"
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, dest)
            copied.append(dest)
        return copied


# MARK: - One device (or a simulator)

def now() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def run_target(label: str, args, devices_by_case: dict[str, list[str]], listing: dict | None) -> int:
    simulator = label == "sim"
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    record_dir = RUNS / label / run_id
    work = (Path(args.work_dir) if args.work_dir else ROOT / "Build/qa-011") / label / run_id
    only = set(args.only.split(",")) if args.only else None
    cases = plan(None if simulator and not args.as_device else (args.as_device or label), devices_by_case, only)

    if simulator:
        listing_sim = json.loads(capture(["xcrun", "simctl", "list", "devices", "--json"]).stdout or "{}")
        runtimes = json.loads(capture(["xcrun", "simctl", "list", "runtimes", "--json"]).stdout or "{}")
        facts = simulator_facts(listing_sim, runtimes, args.simulator)
        identifier, udid = args.simulator, args.simulator
    elif rdt.DRY_RUN:
        facts = {"kind": "device", "identifier": f"<{label} identifier>", "udid": "<UDID>", "state": "dry run"}
        identifier, udid = facts["identifier"], facts["udid"]
    else:
        facts = device_facts(device_entry(listing or {}, label))
        identifier, udid = facts.get("identifier"), facts.get("udid")

    app = Path(args.app) if args.app else rdt.BUILD / (
        f"Build/Products/{'Debug-iphonesimulator' if simulator else 'Release-iphoneos'}/{rdt.SCHEME}.app")
    configuration = args.configuration or ("Debug (simulator rehearsal)" if simulator else "Release+PROJECTM_AUTOMATION")
    evidence = not simulator
    record = {"kind": RECORD_KIND, "schemaVersion": 1, "runId": run_id, "label": label, "evidence": evidence,
              "evidenceNote": "physical device run" if evidence else "simulator rehearsal, not evidence",
              "dryRun": rdt.DRY_RUN, "target": facts, "startedAt": now(), "stopReason": None, "cases": []}

    print(f"\n=== QA-011 matrix: {label} ({facts.get('name') or identifier}), {len(cases)} cases"
          + ("" if evidence else " — SIMULATOR REHEARSAL, NOT EVIDENCE") + " ===", flush=True)
    target = MatrixTarget(label, identifier or "", simulator, record_dir / "artifacts", udid)
    runner = Runner(target, work, args.locked_wait, [Path(p) for p in args.perf012_report], rdt.DRY_RUN)
    runner.rendererlab_app = Path(args.rendererlab_app) if args.rendererlab_app else None
    runner.rebuild_rendererlab = bool(args.build) and not args.rendererlab_app

    unavailable = (not simulator and not rdt.DRY_RUN and facts.get("state") in ("not listed", "unavailable"))
    if args.build:
        rdt.cmd_build(args)
    record["app"], record["signing"], record["host"] = app_facts(app, configuration), signing_facts(app), host_facts()
    if unavailable:
        record["stopReason"] = "unavailable"
        print(f"!! {label} ({rdt.DEVICES[label]}) is {facts.get('state')}: connect the cable, unlock it and trust "
              f"this Mac; nothing ran", flush=True)
        record["cases"] = [dict(runner_result_stub(c), detail=f"device {facts.get('state')}") for c in cases]
    else:
        if simulator and not rdt.DRY_RUN:
            capture(["xcrun", "simctl", "boot", identifier])
        if not args.no_install and any(c["kind"] in ("autorun", "launches", "warmstart", "xctrace") for c in cases):
            try:
                target.uninstall()
                target.install(app)
                runner.fresh_install = True
            except subprocess.CalledProcessError as e:
                record["stopReason"] = "install failed"
                print(f"!! install failed on {label}: {e}", flush=True)
        stopped = record["stopReason"]
        for c in cases:
            if stopped:
                record["cases"].append(dict(runner_result_stub(c), detail=f"not run: {stopped}"))
                continue
            result = runner.run_case(c)
            record["cases"].append(result)
            print(f"--> {c['id']}: {result['status']} {result['detail'][:200]}", flush=True)
            if result["status"] == "blocked":
                stopped = record["stopReason"] = "locked"
                print(f"!! {result['detail']}", flush=True)
            target.terminate()
    record["finishedAt"] = now()
    if rdt.DRY_RUN:
        print(f"(dry run: {len(cases)} cases planned for {label}; nothing written)")
        return 0
    path = write_record(record, record_dir)
    print(f"record: {display_path(path)} sha256 {record['recordSha256']}")
    print(", ".join(f"{k} {v}" for k, v in record["summary"].items() if v))
    if not args.no_install:
        # The reinstall reset Documents and every permission answer (D1, 2026-11-23: a springboard alert over the next
        # UI run). UI tests on this device need the prompt-flow batch first; run_device_ui_tests.sh reseeds fixtures.
        print(f"next on {label}: python3 scripts/mac_device_driver.py prompt-flow --device {label} before any UI test run")
    return 0 if record["summary"]["pass"] == len(cases) else 1


def runner_result_stub(c: dict) -> dict:
    return {"id": c["id"], "kind": c["kind"], "title": c["title"], "closes": c["closes"],
            "partOf": c.get("partOf", []), "status": "not-run", "commands": [], "artifacts": [], "detail": "",
            "durationSeconds": 0.0}


def main(argv: list[str] | None = None) -> int:
    raw = list(sys.argv[1:] if argv is None else argv)
    if raw[:1] == ["verify"]:
        problems = []
        for p in raw[1:]:
            found = verify_record(Path(p))
            problems += [f"{p}: {x}" for x in found]
            print(f"{p}: {'ok' if not found else 'FAILED'}")
        print("\n".join(problems))
        return 1 if problems or len(raw) < 2 else 0
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--device", action="append", choices=[*LABELS, "all"], help="D1, D2, D3 or all (repeatable)")
    parser.add_argument("--simulator", metavar="UDID", help="rehearse on this simulator (not evidence)")
    parser.add_argument("--as-device", choices=LABELS, help="simulator: run only this device's cases")
    parser.add_argument("--dry-run", action="store_true", help="print every command; write nothing")
    parser.add_argument("--build", action="store_true", help="build the measurement build first (run_device_tests build)")
    parser.add_argument("--app", help="the .app to install (default: the measurement build's output)")
    parser.add_argument("--configuration", help="how --app was built, for the record")
    parser.add_argument("--no-install", action="store_true", help="keep the installed app")
    parser.add_argument("--only", help=f"comma-separated case ids ({', '.join(CASE_IDS)})")
    parser.add_argument("--perf012-report", action="append", default=[], help="an exported PERF-012 report for QA-010")
    parser.add_argument("--locked-wait", type=float, default=600, help="seconds a locked device is waited for")
    parser.add_argument("--work-dir", help="where xcresults and logs go (default Build/qa-011)")
    parser.add_argument("--inventory", default=str(INVENTORY))
    parser.add_argument("--rendererlab-app", help="a built RendererLab.app for rendererlab-flashcost (default: rebuilt with --build, else built "
                        "into Build/rendererlab when missing)")
    args = parser.parse_args(raw)
    if bool(args.device) == bool(args.simulator):
        parser.error("give --device D1|D2|D3|all or --simulator <udid>")
    if args.only and (bad := set(args.only.split(",")) - set(CASE_IDS)):
        parser.error(f"unknown case ids: {', '.join(sorted(bad))}")
    rdt.DRY_RUN = args.dry_run
    rdt.LOCKED_WAIT = args.locked_wait
    devices_by_case = case_devices(load_inventory(Path(args.inventory)))
    if args.simulator:
        return run_target("sim", args, devices_by_case, None)
    labels = list(LABELS) if "all" in args.device else list(dict.fromkeys(args.device))
    listing = None
    if not args.dry_run:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "devices.json"
            capture(["xcrun", "devicectl", "list", "devices", "--json-output", str(out)])
            listing = json.loads(out.read_text()) if out.exists() else {}
    return max(run_target(label, args, devices_by_case, listing) for label in labels)


if __name__ == "__main__":
    sys.exit(main())
