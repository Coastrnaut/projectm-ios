"""Files in the app's Documents on the device, for the QA-011 Batch 5 device tests (B07FilesDeviceTests).

    MAC-DO {"action": "files.pull", "prefix": "projectM-iOS Presets ", "suffix": ".zip",
            "present": ["preset-small"], "absent": ["Cream copy"]}
    MAC-DO {"action": "files.push", "from": "D1", "prefix": "projectM-iOS Scene ", "suffix": ".pmscene"}

* `pull` copies the newest Documents file whose name has `prefix` and `suffix` (or exactly `name`) to
  Build/device-files/<device>/ and, for a ZIP, checks its entry names and text entries (manifest.json): every string
  in `present` must appear, none in `absent`. The result line (`MAC-DONE <id> ok …` or `FAIL …`) is the evidence; the
  device test cannot read it (the log reaches the Mac late), so the run's driver log is kept with the test log.
* `push` copies the newest such file pulled earlier from device `from` (Build/device-files/<from>/) into this
  device's Documents, where the Debug device-test host shows it in Files (FILE-001: D1's scene archive to D3).
"""
from __future__ import annotations

import json
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
STORE = ROOT / "Build" / "device-files"


def _device_name(context) -> str:
    """The folder for this device's files: the D-name when the identifier is known, else the identifier."""
    try:
        from mac_driver import devices
        for name, ids in devices.identifiers().items():
            if context.device in ids.values():
                return name
    except Exception:   # noqa: BLE001 - devicectl unavailable (tests, dry runs)
        pass
    return str(context.device)


def _documents(context) -> list[str]:
    listing = context.devicectl_json(["device", "info", "files", "--device", context.device, "--domain-type",
                                      "appDataContainer", "--domain-identifier", context.bundle,
                                      "--subdirectory", "Documents"])
    return [str(f.get("relativePath", "")) for f in listing.get("result", {}).get("files", [])]


def pick(names: list[str], request: dict) -> str | None:
    """`name` itself, or the last (by name: dated names sort by date) with `prefix` and `suffix`."""
    if request.get("name"):
        return str(request["name"])
    prefix, suffix = str(request.get("prefix", "")), str(request.get("suffix", ""))
    found = sorted(n.rsplit("/", 1)[-1] for n in names
                   if n.rsplit("/", 1)[-1].startswith(prefix) and n.endswith(suffix) and "/" not in n.strip("/"))
    return found[-1] if found else None


def zip_text(path: Path) -> str:
    """Entry names, then the content of every small text entry (manifests, presets), one string to search."""
    parts: list[str] = []
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            parts.append(info.filename)
            if info.file_size <= 1_000_000 and info.filename.endswith((".json", ".milk", ".txt")):
                parts.append(z.read(info).decode("utf-8", errors="replace"))
    return "\n".join(parts)


def check(text: str, present: list[str], absent: list[str]) -> list[str]:
    problems = [f"missing {p!r}" for p in present if p not in text]
    problems += [f"unexpected {a!r}" for a in absent if a in text]
    return problems


def pull(request: dict, context) -> str:
    if not context.device:
        raise ValueError("no device (--device)")
    name = pick([] if request.get("name") else _documents(context), request)
    if not name:
        return "FAIL no matching file in Documents"
    target = STORE / _device_name(context) / name
    target.parent.mkdir(parents=True, exist_ok=True)
    result = context.command(["xcrun", "devicectl", "device", "copy", "from", "--device", context.device,
                              "--domain-type", "appDataContainer", "--domain-identifier", context.bundle,
                              "--source", f"Documents/{name}", "--destination", str(target)])
    if result.returncode != 0:
        return f"FAIL copy: {result.stderr.strip()[-200:]}"
    if context.dry_run:
        return f"ok (dry run) {target}"
    detail = f"{target.stat().st_size} bytes"
    if name.endswith(".zip"):
        try:
            problems = check(zip_text(target), list(request.get("present", [])), list(request.get("absent", [])))
        except zipfile.BadZipFile:
            return f"FAIL {name} is not a ZIP"
        with zipfile.ZipFile(target) as z:
            detail += " entries=" + json.dumps(sorted(z.namelist()))
        if problems:
            return f"FAIL {name}: " + "; ".join(problems) + " " + detail
    return f"ok {target} {detail}"


def push(request: dict, context) -> str:
    if not context.device:
        raise ValueError("no device (--device)")
    folder = STORE / str(request.get("from", ""))
    names = [p.name for p in folder.glob("*")] if folder.is_dir() else []
    name = pick(names, request)
    if not name or not (folder / name).exists():
        return f"FAIL nothing pulled from {request.get('from')} yet ({folder})"
    result = context.command(["xcrun", "devicectl", "device", "copy", "to", "--device", context.device,
                              "--domain-type", "appDataContainer", "--domain-identifier", context.bundle,
                              "--source", str(folder / name), "--destination", f"Documents/{name}"])
    return f"ok pushed {name}" if result.returncode == 0 else f"FAIL copy: {result.stderr.strip()[-200:]}"


ACTIONS = {"pull": pull, "push": push}


if __name__ == "__main__":   # a quick self-check of the ZIP test (no device)
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "x.zip"
        with zipfile.ZipFile(path, "w") as z:
            z.writestr("manifest.json", json.dumps({"presets": ["preset-small"]}))
        assert check(zip_text(path), ["preset-small"], ["Cream copy"]) == []
        assert check(zip_text(path), ["other"], ["preset"]) == ["missing 'other'", "unexpected 'preset'"]
        assert pick(["Documents/a.zip", "projectM-iOS Presets 2026-11-17.zip", "projectM-iOS Presets 2026-11-18.zip"],
                    {"prefix": "projectM-iOS Presets ", "suffix": ".zip"}) == "projectM-iOS Presets 2026-11-18.zip"
        print("files.py self-check ok")
