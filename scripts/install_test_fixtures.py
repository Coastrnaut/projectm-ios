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
    args = p.parse_args(argv)
    for name, variant in zip(FIXTURES, ["normal", "left", "inverted"]):
        if not (ROOT / "Build" / "fixtures" / name).exists():
            subprocess.run([sys.executable, str(ROOT / "scripts" / "make_music_fixture.py"), "--variant", variant], check=True)
    sources = [ROOT / "Build" / "fixtures" / f for f in FIXTURES]
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
        for source in sources:
            result = subprocess.run(copy_command(ids[name], source), capture_output=True, text=True)
            ok = result.returncode == 0
            print(f"install_test_fixtures: {name} {source.name} {'copied' if ok else 'FAILED: ' + result.stderr.strip()[-200:]}")
            status |= 0 if ok else 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
