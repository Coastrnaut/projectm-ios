#!/usr/bin/env python3
"""QA-011 B09: the "controller on another computer" for the OSC device tests, run on the Mac beside xcodebuild.

The device test (Apps/projectM-iOS/DeviceUITests/B09OSCDeviceTests.swift) prints `OSC-READY <scenario>` in the
xcodebuild log once the app listens; this script follows that log and answers each scenario by sending OSC over UDP
to the device's Bonjour name (iPhone77.local etc.), then prints what it sent. Local network only; nothing leaves the
LAN. Scenarios:
  test    /projectm/test ,f 0.42                                    (OSC-001-T26)
  flood   /projectm/test at about 2,000 msg/s for 10 s, last 0.77   (OSC-009-T15)
  bundle  0.33 now, a bundle 2 s ahead (0.55) and one 30 s ahead (0.66) (OSC-006-T11; the plain 0.33 marks
          the send time on the device, since the log reaches this script late)
  after   /projectm/test ,f 0.11 after Stop                         (OSC-007-T12: must not arrive)

    python3 scripts/osc_device_driver.py --log .autonomous/logs/b09-D1.log --host iPhone77.local [--port 9000]
"""
from __future__ import annotations

import argparse
import socket
import struct
import time
from pathlib import Path

NTP_EPOCH = 2_208_988_800   # seconds from 1900 to 1970


def pad(b: bytes) -> bytes:
    return b + b"\0" * (4 - len(b) % 4)


def message(address: str, value: float) -> bytes:
    return pad(address.encode()) + pad(b",f") + struct.pack(">f", value)


def bundle(at: float, *messages: bytes) -> bytes:
    seconds = at + NTP_EPOCH
    timetag = struct.pack(">II", int(seconds), int((seconds % 1) * 2**32))
    return pad(b"#bundle") + timetag + b"".join(struct.pack(">i", len(m)) + m for m in messages)


def run(scenario: str, sock: socket.socket, target: tuple[str, int]) -> str:
    if scenario == "test":
        sock.sendto(message("/projectm/test", 0.42), target)
        return "0.42"
    if scenario == "after":
        sock.sendto(message("/projectm/test", 0.11), target)
        return "0.11"
    if scenario == "bundle":
        now = time.time()
        sock.sendto(message("/projectm/test", 0.33), target)
        sock.sendto(bundle(now + 2, message("/projectm/test", 0.55)), target)
        sock.sendto(bundle(now + 30, message("/projectm/test", 0.66)), target)
        return "0.33 now, 0.55 at +2 s, 0.66 at +30 s"
    if scenario == "flood":
        start, n = time.monotonic(), 0
        while time.monotonic() - start < 10:
            sock.sendto(message("/projectm/test", (n % 100) / 100), target)
            n += 1
            time.sleep(max(0, start + n / 2000 - time.monotonic()))
        sock.sendto(message("/projectm/test", 0.77), target)
        return f"{n + 1} messages, last 0.77"
    return "unknown scenario"


def resolve(host: str) -> str:
    """The device's address: the resolver, else macOS's Bonjour cache (`dscacheutil`), which resolves `<name>.local`
    when Python's resolver does not (seen 2026-11-16)."""
    try:
        return socket.gethostbyname(host)
    except OSError:
        import subprocess
        out = subprocess.run(["dscacheutil", "-q", "host", "-a", "name", host], capture_output=True, text=True).stdout
        for line in out.splitlines():
            if line.startswith("ip_address:") and "." in line:
                return line.split(":", 1)[1].strip()
        raise


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--log", required=True)
    p.add_argument("--host", required=True)
    p.add_argument("--port", type=int, default=9000)
    p.add_argument("--timeout", type=float, default=900)
    args = p.parse_args(argv)
    target = (resolve(args.host), args.port)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    log, done, seen = Path(args.log), time.monotonic() + args.timeout, 0
    print(f"osc_device_driver: {args.host} = {target[0]}:{target[1]}", flush=True)
    while time.monotonic() < done:
        lines = log.read_text(errors="replace").splitlines() if log.exists() else []
        for line in lines[seen:]:
            if "OSC-READY " in line:
                scenario = line.split("OSC-READY ", 1)[1].split()[0]
                print(f"osc_device_driver: {scenario}: sent {run(scenario, sock, target)}", flush=True)
            if "** TEST" in line or "Testing failed" in line or "Test Suite 'All tests' " in line and "passed" in line:
                return 0
        seen = len(lines)
        time.sleep(0.2)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
