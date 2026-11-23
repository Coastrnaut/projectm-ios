#!/usr/bin/env python3
"""QA-011: copy the device-test fixtures into the app's Documents on D1-D3 (devicectl, over Wi-Fi).

The on-device acceptance tests play the generated music fixture (`scripts/make_music_fixture.py`) from the app's
Documents; a device without it stays on "Choose source" and every test fails at launch (D3, 2026-11-16). Run this
once per device after the app is installed (a fresh install or an uninstall empties Documents).

`--media` also copies the media fixtures (pictures, videos, audio formats, presets: scripts/make_media_fixtures.py,
made first when missing) from Build/fixtures/media. The Debug device-test host shows Documents in Files (On My
iPhone/iPad › projectM), so tests can pick them with the real document picker (DeviceTests.yml).

    python3 scripts/install_test_fixtures.py --device all [--media] [--only photo-gps.heic …]
    python3 scripts/install_test_fixtures.py --device-id <devicectl identifier> --media   # mac_device_driver.py
    python3 scripts/install_test_fixtures.py --device D3 --media --if-missing   # run_device_ui_tests.sh, every run

`--if-missing` lists the app's Documents first and copies only the files that are not there: the matrix runner
reinstalls the app, which empties Documents, and the next UI run then failed at launch on every music test (D2 and D3,
2026-11-23: "music-fixture.m4a is missing"), so run_device_ui_tests.sh seeds before every run.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = "org.projectmios.ProjectMiOS"
DEVICES = {"D1": "iPhone15,4", "D2": "iPad17,3", "D3": "iPad15,7"}
FIXTURES = ["music-fixture.m4a", "music-fixture-left.m4a", "music-fixture-inverted.m4a"]   # B05: left-only, inverted
MEDIA = ROOT / "Build" / "fixtures" / "media"


def media_fixtures(only: list[str] | None = None) -> list[Path]:
    """The media fixtures to copy: every catalogued file (made when missing), or `only` those."""
    import make_media_fixtures as mmf
    names = only or list(mmf.CATALOG)
    missing = [n for n in names if not (MEDIA / n).exists()]
    if missing:
        mmf.make(missing, MEDIA)
    return [MEDIA / n for n in names if (MEDIA / n).exists()]


def copy_command(device: str, source: Path) -> list[str]:
    return ["xcrun", "devicectl", "device", "copy", "to", "--device", device, "--domain-type", "appDataContainer",
            "--domain-identifier", BUNDLE, "--source", str(source), "--destination", f"Documents/{source.name}"]


# AUD-002-T25: MP3 from a real encoder (lame; owner approved 2026-11-18), constant and variable bit rate.
MP3_FIXTURES = {"music-fixture-cbr.mp3": "cbr", "music-fixture-vbr.mp3": "vbr"}


def documents(device: str) -> set[str] | None:
    """The file names in the app's Documents on `device`, or None when the listing fails (then everything is copied)."""
    with tempfile.NamedTemporaryFile(suffix=".json") as out:
        result = subprocess.run(["xcrun", "devicectl", "device", "info", "files", "--device", device, "--domain-type",
                                 "appDataContainer", "--domain-identifier", BUNDLE, "--subdirectory", "Documents",
                                 "--json-output", out.name], capture_output=True, text=True)
        if result.returncode != 0:
            return None
        try:
            return parse_listing(json.loads(Path(out.name).read_text()))
        except (ValueError, KeyError):
            return None


def parse_listing(data: dict) -> set[str]:
    files = data.get("result", {}).get("files", [])
    return {Path(f.get("relativePath") or f.get("name") or "").name for f in files} - {""}


def identifiers() -> dict[str, str]:
    with tempfile.NamedTemporaryFile(suffix=".json") as out:
        subprocess.run(["xcrun", "devicectl", "list", "devices", "--json-output", out.name],
                       check=True, capture_output=True)
        devices = json.loads(Path(out.name).read_text())["result"]["devices"]
    by_type = {d["hardwareProperties"].get("productType"): d["identifier"] for d in devices}
    return {name: by_type[t] for name, t in DEVICES.items() if t in by_type}


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--device", choices=["D1", "D2", "D3", "all"], default="all")
    p.add_argument("--device-id", help="a devicectl identifier instead of --device")
    p.add_argument("--media", action="store_true", help="also copy the media fixtures (Build/fixtures/media)")
    p.add_argument("--only", nargs="+", help="with --media: only these media fixtures")
    p.add_argument("--if-missing", action="store_true", help="copy only the files not already in Documents")
    args = p.parse_args(argv)
    for name, variant in zip(FIXTURES, ["normal", "left", "inverted"]):
        if not (ROOT / "Build" / "fixtures" / name).exists():
            subprocess.run([sys.executable, str(ROOT / "scripts" / "make_music_fixture.py"), "--variant", variant], check=True)
    sources = [ROOT / "Build" / "fixtures" / f for f in FIXTURES]
    for name, kind in MP3_FIXTURES.items():   # AUD-002-T25: made with lame when missing
        if not (ROOT / "Build" / "fixtures" / name).exists():
            made = subprocess.run([sys.executable, str(ROOT / "scripts" / "make_music_fixture.py"), "--mp3", kind]).returncode == 0
            if not made:
                print(f"install_test_fixtures: {name} not made (needs lame); AUD-002-T25's MP3 cases will fail")
                continue
        sources.append(ROOT / "Build" / "fixtures" / name)
    if args.media:
        sys.path.insert(0, str(ROOT / "scripts"))
        sources += media_fixtures(args.only)
    if args.device_id:
        ids, wanted = {"device": args.device_id}, ["device"]
    else:
        ids = identifiers()
        wanted = list(DEVICES) if args.device == "all" else [args.device]
    status = 0
    for name in wanted:
        if name not in ids:
            print(f"install_test_fixtures: {name} not found (paired and on the network?)")
            status = 1
            continue
        present = documents(ids[name]) if args.if_missing else None
        todo = [s for s in sources if present is None or s.name not in present]
        if args.if_missing:
            print(f"install_test_fixtures: {name} {len(sources) - len(todo)} present, {len(todo)} to copy")
        for source in todo:
            result = subprocess.run(copy_command(ids[name], source), capture_output=True, text=True)
            ok = result.returncode == 0
            print(f"install_test_fixtures: {name} {source.name} {'copied' if ok else 'FAILED: ' + result.stderr.strip()[-200:]}")
            status |= 0 if ok else 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
