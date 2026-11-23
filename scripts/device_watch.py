#!/usr/bin/env python3
"""Watch device test runs and exit as soon as one needs attention (QA-011, owner rule 2026-11-23).

On 2026-11-23 the owner saw D1 and D3 "hung up on a test": D3's run had been silent for 15 minutes before the runner's
watchdog stopped it, and D1's queue had finished 15 minutes earlier with the app's last screen still showing. The
waiters only reported when a whole queue ended, so neither was noticed. This watcher is run in the background
alongside every device run; it exits (which wakes the session) the moment any watched device:

* has a live `xcodebuild test` whose newest log has been silent for `--silent` seconds (default 300), or
* has no live `xcodebuild test` (its queue ended or the run died): the device is idle.

It prints one line per device that needs attention, e.g. `D3 SILENT 6 min: <log>: last test <name>` or
`D1 IDLE: last log <log> ended <time>`, then exits 1. `--devices D1,D3` picks the devices (default D1,D2,D3).
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOGS = ROOT / ".autonomous" / "logs"
UDIDS = {"D1": "00008120-001E4C5C3A42201E", "D2": "00008142-001640823C22401C", "D3": "00008120-000165E830914032"}


def live_runs() -> str:
    return subprocess.run(["ps", "-axo", "command"], capture_output=True, text=True).stdout


def running(device: str, ps: str) -> bool:
    """A device test run (`xcodebuild test` on its UDID) or a matrix run (`run_device_matrix.py --device <D>`, which
    launches through devicectl between its xcodebuild cases)."""
    udid = UDIDS[device]
    for line in ps.splitlines():
        if "xcodebuild" in line and " test" in line and udid in line:
            return True
        if "run_device_matrix.py" in line and re.search(rf"--device(=| ){device}\b", line):
            return True
    return False


def newest_log(device: str) -> Path | None:
    logs = [p for p in LOGS.glob(f"*-{device.lower()}.log")]
    return max(logs, key=lambda p: p.stat().st_mtime) if logs else None


def last_test(log: Path) -> str:
    started = ""
    with log.open(errors="replace") as handle:
        for line in handle:
            m = re.search(r"Test Case '-\[\S+ (\S+)\]' started", line)
            if m:
                started = m.group(1)
    return started or "none"


def check(devices: list[str], silent: float, now: float, ps: str) -> list[str]:
    alerts = []
    for device in devices:
        log = newest_log(device)
        age = now - log.stat().st_mtime if log else float("inf")
        if not running(device, ps):
            alerts.append(f"{device} IDLE: no xcodebuild test running; last log {log.name if log else 'none'} "
                          f"{int(age // 60)} min ago")
        elif age >= silent:
            alerts.append(f"{device} SILENT {int(age // 60)} min: {log.name}: last test {last_test(log)}")
    return alerts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--devices", default="D1,D2,D3")
    parser.add_argument("--silent", type=float, default=300, help="seconds of log silence that count as a stall")
    parser.add_argument("--poll", type=float, default=30)
    parser.add_argument("--grace", type=float, default=90, help="seconds before the first idle check (runs starting)")
    args = parser.parse_args()
    devices = [d.strip().upper() for d in args.devices.split(",") if d.strip()]
    started = time.time()
    while True:
        now = time.time()
        alerts = check(devices, args.silent, now, live_runs())
        if now - started < args.grace:
            alerts = [a for a in alerts if "IDLE" not in a]
        if alerts:
            print("\n".join(alerts), flush=True)
            return 1
        time.sleep(args.poll)


if __name__ == "__main__":
    sys.exit(main())
