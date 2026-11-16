#!/usr/bin/env python3
"""QA-011: copy the device-test fixtures into the app's Documents on D1-D3 (devicectl, over Wi-Fi).

The on-device acceptance tests play the generated music fixture (`scripts/make_music_fixture.py`) from the app's
Documents; a device without it stays on "Choose source" and every test fails at launch (D3, 2026-11-16). Run this
once per device after the app is installed (a fresh install or an uninstall empties Documents).

    python3 scripts/install_test_fixtures.py --device all
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
    args = p.parse_args(argv)
    for name, variant in zip(FIXTURES, ["normal", "left", "inverted"]):
        if not (ROOT / "Build" / "fixtures" / name).exists():
            subprocess.run([sys.executable, str(ROOT / "scripts" / "make_music_fixture.py"), "--variant", variant], check=True)
    ids = identifiers()
    wanted = list(DEVICES) if args.device == "all" else [args.device]
    status = 0
    for name in wanted:
        if name not in ids:
            print(f"install_test_fixtures: {name} not found (paired and on the network?)")
            status = 1
            continue
        for fixture in FIXTURES:
            result = subprocess.run(["xcrun", "devicectl", "device", "copy", "to", "--device", ids[name],
                                     "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE,
                                     "--source", str(ROOT / "Build" / "fixtures" / fixture),
                                     "--destination", f"Documents/{fixture}"],
                                    capture_output=True, text=True)
            ok = result.returncode == 0
            print(f"install_test_fixtures: {name} {fixture} {'copied' if ok else 'FAILED: ' + result.stderr.strip()[-200:]}")
            status |= 0 if ok else 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
