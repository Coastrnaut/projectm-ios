#!/usr/bin/env python3
"""QA-003-T17: turn the device goldens a RenderGoldens run recorded on a device into a committed golden class.

On a device the test bundle is read-only, so `RECORD_DEVICE_GOLDENS=1` (TEST_RUNNER_RECORD_DEVICE_GOLDENS=1 on the
xcodebuild command; matrix case `xctest-goldens-record`) makes GoldenRenderSuiteTests attach one JSON per capture
(kind `projectM-iOS.deviceGolden`: the golden class, the manifest entry, the PNG in base64). This script reads those
attachments (exported with `xcrun xcresulttool export attachments`) and writes
Packages/RenderGoldens/Goldens/<class>/ with its PNGs and a canonical manifest.json (the format of GoldenManifest:
sorted keys, " : " separators, entries sorted by scene, width, frame, trailing newline). Rebuild the device test
bundle afterwards: the folder is bundled, and the next run compares against it.

    python3 scripts/import_device_goldens.py <attachments folder or .xcresult> [--dest Packages/RenderGoldens/Goldens]
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "Packages/RenderGoldens/Goldens"
KIND = "projectM-iOS.deviceGolden"


def read_captures(folder: Path) -> list[dict]:
    out = []
    for path in sorted(folder.rglob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(data, dict) and data.get("kind") == KIND:
            out.append(data)
    return out


def canonical_manifest(manifest: dict) -> str:
    entries = sorted(manifest["entries"], key=lambda e: (e["scene"], e["width"], e["frame"]))
    return json.dumps({**manifest, "entries": entries}, indent=2, sort_keys=True, separators=(",", " : "),
                      ensure_ascii=False) + "\n"


def build(captures: list[dict]) -> tuple[str, dict, dict[str, bytes]]:
    """(class, manifest, file name -> PNG bytes); checks every PNG against its entry's file hash."""
    classes = {c["goldenClass"] for c in captures}
    if len(classes) != 1:
        raise ValueError(f"expected captures of one device golden class, found {sorted(classes) or 'none'}")
    golden_class = classes.pop()
    files: dict[str, bytes] = {}
    entries: dict[tuple, dict] = {}
    os_versions, gpus = set(), set()
    for c in captures:
        entry, png = c["entry"], base64.b64decode(c["png"])
        if hashlib.sha256(png).hexdigest() != entry["fileSHA256"]:
            raise ValueError(f"{entry['file']}: PNG does not match its fileSHA256")
        files[entry["file"]] = png
        entries[(entry["scene"], entry["width"], entry["frame"])] = entry
        os_versions.add(c["recordedOS"])
        gpus.add(c["recordedGPU"])
    if len(os_versions) != 1:
        raise ValueError(f"captures from several OS versions: {sorted(os_versions)}")
    manifest = {"formatVersion": 1, "platform": golden_class, "recordedOS": os_versions.pop(),
                "recordedGPU": sorted(gpus)[0], "entries": list(entries.values())}
    return golden_class, manifest, files


def write(golden_class: str, manifest: dict, files: dict[str, bytes], dest: Path) -> Path:
    folder = dest / golden_class
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("*.png"):   # a re-record replaces the class
        if old.name not in files:
            old.unlink()
    for name, png in files.items():
        (folder / name).write_bytes(png)
    (folder / "manifest.json").write_text(canonical_manifest(manifest), encoding="utf-8")
    return folder


def export_attachments(xcresult: Path, out: Path) -> Path:
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(xcresult), "--output-path", str(out)],
                   check=True, capture_output=True)
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source", help="exported attachments folder, or an .xcresult bundle")
    parser.add_argument("--dest", default=str(DEST))
    args = parser.parse_args(argv)
    source = Path(args.source)
    with tempfile.TemporaryDirectory() as tmp:
        folder = export_attachments(source, Path(tmp) / "a") if source.suffix == ".xcresult" else source
        captures = read_captures(folder)
        if not captures:
            print(f"no {KIND} attachments in {source} (was RECORD_DEVICE_GOLDENS=1 set?)")
            return 1
        golden_class, manifest, files = build(captures)
        out = write(golden_class, manifest, files, Path(args.dest))
    print(f"{out}: {len(files)} goldens, recorded on {manifest['recordedOS']} ({manifest['recordedGPU']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
