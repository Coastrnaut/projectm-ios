#!/usr/bin/env python3
"""Clear a leftover REC-015/REC-009 disk ballast from a test device (QA-011, 2026-11-24).

The DEBUG disk ballast (`Apps/projectM-iOS/Debug/UITestDiskBallast.swift`) fills the device's volume with one file,
`Library/Caches/QA011-DiskBallast.bin`, so the recording disk guard meets real low storage. Every DEBUG launch deletes
an old ballast, and the tests relaunch once in tearDown. On 2026-11-24 D3 was nearly full: a 67 GB ballast from a run
the evening before had stayed because no launch followed (the run was stopped), and with the disk full the next runs
could not launch the test runner at all. devicectl cannot delete a file in an app's container, so this script launches
the app once (its launch deletes the ballast), checks the file is gone and stops the app. If the launch cannot clear it,
it says how big the file is and that uninstalling the app frees it.

`run_device_ui_tests.sh` runs it after every device run; it can also be run by hand:
`python3 scripts/clear_disk_ballast.py --device D3`. Exit 0 when no ballast is left, 1 when one is still there.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from install_test_fixtures import BUNDLE, identifiers  # noqa: E402

BALLAST = "QA011-DiskBallast.bin"


def ballast_size(data: dict) -> int | None:
    """The ballast's size in bytes from devicectl's `Library/Caches` listing, or None when there is none."""
    for f in data.get("result", {}).get("files", []):
        if Path(f.get("relativePath") or f.get("name") or "").name == BALLAST:
            return int((f.get("metadata") or {}).get("size") or 0)
    return None


def caches_listing(device: str) -> dict | None:
    with tempfile.NamedTemporaryFile(suffix=".json") as out:
        result = subprocess.run(["xcrun", "devicectl", "device", "info", "files", "--device", device, "--domain-type",
                                 "appDataContainer", "--domain-identifier", BUNDLE, "--subdirectory", "Library/Caches",
                                 "--json-output", out.name], capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            return None   # not installed (nothing to clear) or the device is unreachable
        return json.loads(Path(out.name).read_text())


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--device", choices=["D1", "D2", "D3"], required=True)
    p.add_argument("--wait", type=float, default=30, help="seconds to wait for the launch to delete the ballast")
    args = p.parse_args(argv)
    device = identifiers().get(args.device)
    if not device:
        print(f"clear_disk_ballast: {args.device} not connected; nothing checked")
        return 0
    listing = caches_listing(device)
    size = ballast_size(listing) if listing else None
    if size is None:
        print(f"clear_disk_ballast: {args.device}: no ballast")
        return 0
    print(f"clear_disk_ballast: {args.device}: ballast {size / 1e9:.1f} GB left over; launching the app to delete it")
    subprocess.run(["xcrun", "devicectl", "device", "process", "launch", "--device", device, "--terminate-existing",
                    BUNDLE], capture_output=True, text=True, timeout=120)
    deadline = time.time() + args.wait
    while time.time() < deadline:
        time.sleep(3)
        listing = caches_listing(device)
        if listing is not None and ballast_size(listing) is None:
            print(f"clear_disk_ballast: {args.device}: ballast deleted")
            return 0
    print(f"clear_disk_ballast: {args.device}: the ballast ({size / 1e9:.1f} GB) is still there; uninstall the app "
          f"(xcrun devicectl device uninstall app --device {device} {BUNDLE}) to free it")
    return 1


if __name__ == "__main__":
    sys.exit(main())
