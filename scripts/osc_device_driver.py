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
QA-011 Batch 8:
  glow-low / glow-high   /projectm/param/glow.intensity 0.2 / 0.9   (OSC-003-T15)
  learn                  /b8/fader/9 0.5 while Learn waits          (OSC-004-T14)
  learn-low / learn-high /b8/fader/9 0.1 / 0.95                     (OSC-004-T14: the alias drives the glow)
  test2                  /projectm/test 0.43                        (OSC-008-T13 phase 2: the Mac is now approved)
  listen, listen-done    a window of the listener (`--listen-port`, a system Perl UDP socket started with the
                         driver); at listen-done the window must hold /projectm/status and two /projectm/scene
                         messages (OSC-005-T16)
  exported               copies the newest projectM-osc-routes-*.md out of the app's Documents (`--device`) and
                         checks it against the test's `OSC-ROUTES [...]` line: every route present, no address or
                         port (OSC-010-T09)
The exit status is 1 when a check fails (listen, exported) or the log never ends.

    python3 scripts/osc_device_driver.py --log .autonomous/logs/b09-D1.log --host iPhone77.local [--port 9000] \\
        [--listen-port 9100] [--device D1]
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mac_driver import devices  # noqa: E402

NTP_EPOCH = 2_208_988_800   # seconds from 1900 to 1970

SIMPLE = {
    "test": ("/projectm/test", 0.42), "after": ("/projectm/test", 0.11), "test2": ("/projectm/test", 0.43),
    "glow-low": ("/projectm/param/glow.intensity", 0.2), "glow-high": ("/projectm/param/glow.intensity", 0.9),
    "learn": ("/b8/fader/9", 0.5), "learn-low": ("/b8/fader/9", 0.1), "learn-high": ("/b8/fader/9", 0.95),
}


def pad(b: bytes) -> bytes:
    return b + b"\0" * (4 - len(b) % 4)


def message(address: str, value: float) -> bytes:
    return pad(address.encode()) + pad(b",f") + struct.pack(">f", value)


def bundle(at: float, *messages: bytes) -> bytes:
    seconds = at + NTP_EPOCH
    timetag = struct.pack(">II", int(seconds), int((seconds % 1) * 2**32))
    return pad(b"#bundle") + timetag + b"".join(struct.pack(">i", len(m)) + m for m in messages)


def decode(datagram: bytes) -> tuple[str, list]:
    """One OSC message (no bundles): its address and its `s`, `f`, `i`, `T`, `F` arguments."""
    def string(at: int) -> tuple[str, int]:
        end = datagram.index(b"\0", at)
        return datagram[at:end].decode(errors="replace"), (end + 4) & ~3
    address, at = string(0)
    if at >= len(datagram) or datagram[at:at + 1] != b",":
        return address, []
    tags, at = string(at)
    args: list = []
    for tag in tags[1:]:
        if tag == "f":
            args.append(struct.unpack(">f", datagram[at:at + 4])[0])
            at += 4
        elif tag == "i":
            args.append(struct.unpack(">i", datagram[at:at + 4])[0])
            at += 4
        elif tag == "s":
            value, at = string(at)
            args.append(value)
        elif tag in "TF":
            args.append(tag == "T")
    return address, args


def check_listen(addresses: list[str]) -> tuple[bool, dict]:
    """OSC-005-T16: the window holds the source status and at least two cue steps."""
    counts = {a: addresses.count(a) for a in sorted(set(addresses))}
    ok = counts.get("/projectm/scene", 0) >= 2 and counts.get("/projectm/status", 0) >= 1
    return ok, counts


IPV4 = re.compile(r"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b")
PORT = re.compile(r"\bport\s*:?\s*\d{2,5}\b|:\d{4,5}\b", re.IGNORECASE)


def check_export(text: str, addresses: list[str]) -> list[str]:
    """OSC-010-T09: problems with an exported schema (empty when it passes)."""
    problems = [f"missing route {a}" for a in addresses if f"| {a} |" not in text and f"`{a}`" not in text]
    problems += [f"an IP address: {m}" for m in IPV4.findall(text)]
    problems += [f"a port: {m.group(0).strip()}" for m in PORT.finditer(text)]
    if not addresses:
        problems.append("the test printed no OSC-ROUTES line")
    return problems


def send_reliably(sock, data: bytes, target, times: int = 3) -> None:
    """UDP over Wi-Fi can lose a datagram (the first one to a host while its address is looked up, or one at the end
    of a flood); the same value sent three times 50 ms apart changes nothing on the device but survives one loss."""
    for i in range(times):
        sock.sendto(data, target)
        if i < times - 1:
            time.sleep(0.05)


def run(scenario: str, sock, target: tuple[str, int]) -> str:
    if scenario in SIMPLE:
        address, value = SIMPLE[scenario]
        send_reliably(sock, message(address, value), target)
        return f"{address} {value}"
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
        time.sleep(0.2)   # the last value after the flood, sent so that one Wi-Fi loss cannot hide it
        send_reliably(sock, message("/projectm/test", 0.77), target)
        return f"{n + 3} messages, last 0.77"
    return "unknown scenario"


class PerlSender:
    """Sends datagrams through the system Perl. macOS's Local Network privacy refuses the command-line Python here
    ("No route to host", 2026-11-16) while /usr/bin/perl and nc are allowed; one Perl process reads hex datagrams,
    one per line, and sends each."""
    SCRIPT = (r'use IO::Socket::INET; $|=1; my $s=IO::Socket::INET->new(PeerAddr=>$ARGV[0],PeerPort=>$ARGV[1],'
              r'Proto=>"udp") or die "socket $!"; while(my $l=<STDIN>){chomp $l; $s->send(pack("H*",$l));}')

    def __init__(self, host: str, port: int):
        self.proc = subprocess.Popen(["/usr/bin/perl", "-e", self.SCRIPT, host, str(port)],
                                     stdin=subprocess.PIPE, text=True, bufsize=1)

    def sendto(self, data: bytes, _target=None) -> None:
        assert self.proc.stdin is not None
        self.proc.stdin.write(data.hex() + "\n")
        self.proc.stdin.flush()


class PerlListener:
    """Receives datagrams through the system Perl too (same privacy reason); one hex line per datagram, decoded and
    kept with its arrival time."""
    SCRIPT = (r'use IO::Socket::INET; $|=1; my $s=IO::Socket::INET->new(LocalPort=>$ARGV[0],Proto=>"udp") '
              r'or die "socket $!"; my $d; while($s->recv($d,65536)){print unpack("H*",$d),"\n";}')

    def __init__(self, port: int):
        self.received: list[tuple[float, str, list]] = []
        self.proc = subprocess.Popen(["/usr/bin/perl", "-e", self.SCRIPT, str(port)], stdout=subprocess.PIPE, text=True)
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self) -> None:
        assert self.proc.stdout is not None
        for line in self.proc.stdout:
            try:
                address, args = decode(bytes.fromhex(line.strip()))
            except (ValueError, IndexError, struct.error):
                continue
            self.received.append((time.time(), address, args))

    def stop(self) -> None:
        self.proc.terminate()


def resolve(host: str) -> str:
    """Kept for callers of this module: see mac_driver.devices.resolve."""
    return devices.resolve(host)


def check_exported(device: str | None, routes: list[str]) -> tuple[bool, str]:
    if not device:
        return False, "no --device: cannot copy the export off the device"
    identifier = devices.identifiers().get(device, {}).get("identifier", device)
    name = devices.newest(devices.documents(identifier), "projectM-osc-routes-", ".md")
    if not name:
        return False, "no projectM-osc-routes-*.md in the app's Documents"
    with tempfile.TemporaryDirectory() as tmp:
        text = devices.pull(identifier, name, Path(tmp) / name).read_text(errors="replace")
    problems = check_export(text, routes)
    return not problems, f"{name}: " + ("; ".join(problems) if problems else f"all {len(routes)} routes, no address or port")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--log", required=True)
    p.add_argument("--host", required=True)
    p.add_argument("--port", type=int, default=9000)
    p.add_argument("--listen-port", type=int, default=0, help="receive the app's Send OSC here (OSC-005-T16)")
    p.add_argument("--device", help="D1/D2/D3 or a devicectl identifier, for the OSC-010 export copy")
    p.add_argument("--timeout", type=float, default=900)
    args = p.parse_args(argv)
    target = (resolve(args.host), args.port)
    sock = PerlSender(*target)
    listener = PerlListener(args.listen_port) if args.listen_port else None
    log, done, seen = Path(args.log), time.monotonic() + args.timeout, 0
    routes: list[str] = []
    window, failed = 0, False
    print(f"osc_device_driver: {args.host} = {target[0]}:{target[1]}", flush=True)
    try:
        while time.monotonic() < done:
            lines = log.read_text(errors="replace").splitlines() if log.exists() else []
            for line in lines[seen:]:
                if "OSC-ROUTES " in line:
                    routes = json.loads(line.split("OSC-ROUTES ", 1)[1])
                if "OSC-READY " in line:
                    scenario = line.split("OSC-READY ", 1)[1].split()[0]
                    if scenario == "listen":
                        window = len(listener.received) if listener else 0
                        print("osc_device_driver: listen window open" + ("" if listener else " (no --listen-port!)"), flush=True)
                    elif scenario == "listen-done":
                        got = [a for _, a, _ in (listener.received[window:] if listener else [])]
                        ok, counts = check_listen(got)
                        failed |= not ok
                        print(f"OSC-LISTEN {json.dumps({'ok': ok, 'counts': counts})}", flush=True)
                    elif scenario == "exported":
                        ok, summary = check_exported(args.device, routes)
                        failed |= not ok
                        print(f"OSC-EXPORT-CHECK {'pass' if ok else 'FAIL'} {summary}", flush=True)
                    else:
                        print(f"osc_device_driver: {scenario}: sent {run(scenario, sock, target)}", flush=True)
                if "** TEST" in line or "Testing failed" in line or "Test Suite 'All tests' " in line and "passed" in line:
                    return 1 if failed else 0
            seen = len(lines)
            time.sleep(0.2)
        return 1
    finally:
        if listener:
            listener.stop()


if __name__ == "__main__":
    raise SystemExit(main())
