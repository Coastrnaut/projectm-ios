#!/usr/bin/env python3
"""QA-011 Batch 8: the MIDI controller on the Mac for B10MIDIDeviceTests, over a CoreMIDI network session.

Builds scripts/fixtures/midi_session.swift once (Build/mac-tools/midi_session), connects the Mac's network session
to the device (its Bonjour address, RTP-MIDI port 5004), follows the xcodebuild log and answers each
`MIDI-READY <scenario>` line with the scenario's commands (`SCENARIOS`). MIDI-009's feedback check counts the
messages the device sends back in a window (`MIDI-FEEDBACK {json}`); the exit status is 1 when a check fails or the
helper cannot run.

Two prerequisites, neither changed by this script:
* the Mac's network session is enabled (owner, once: Audio MIDI Setup › MIDI Studio › Network › Session 1);
* the app accepts a network session in a DEBUG build: it does not today. The app drops network-attributed MIDI
  endpoints by design (MIDI-001-R2, R14; ADR-0038) and scripts/check_compliance.py and check_network_symbols.py
  reject `MIDINetwork*` in any app source, DEBUG included. Until the proposed DEBUG exemption lands, the device
  tests skip with that message (QA-011 Batch 8 report).

    python3 scripts/mac_driver/midi.py --log <xcodebuild log> --host iPhone77.local [--port 5004]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from mac_driver import devices  # noqa: E402

HELPER_SOURCE = ROOT / "scripts" / "fixtures" / "midi_session.swift"
HELPER = ROOT / "Build" / "mac-tools" / "midi_session"

# Scenario → helper commands (channel 0 = MIDI channel 1). Every task's bytes are here, so they are tested on any OS.
SCENARIOS: dict[str, list[str]] = {
    "monitor": ["sweep 0 7 0 127 8 30", "note 0 60 100", "sleep 100", "off 0 60", "note 0 64 100", "sleep 100", "off 0 64"],
    "monitor-closed": ["cc 0 7 99", "cc 0 7 98", "cc 0 7 97"],                          # MIDI-002: nothing may arrive
    "learn21": ["sweep 0 21 0 127 4 20"],                                               # MIDI-003
    "cc21-low": ["cc 0 21 10"], "cc21-high": ["cc 0 21 120"],                           # MIDI-003, MIDI-012
    "cc21-0": ["cc 0 21 0"], "cc21-127": ["cc 0 21 127"],                               # MIDI-004 (inverted)
    "learn14": ["cc14 0 1 4096", "sleep 200", "cc14 0 1 8192", "sleep 200", "cc14 0 1 12288"],   # MIDI-005
    "ramp14": ["ramp14 0 1 2000 4"],                                                    # MIDI-005: 0→16383 in 8 s
    "pad60": ["note 0 60 100", "sleep 150", "note 0 60 0"],                             # MIDI-006: vel-0 note-on = off
    "hold61": ["note 0 61 100", "sleep 4000", "off 0 61"],                              # MIDI-006: hold for 4 s
    "hold61-long": ["note 0 61 100"],                                                   # MIDI-013: held until Panic
    "release61": ["off 0 61"],
    "pad61": ["note 0 61 100", "sleep 300", "off 0 61"],                                # MIDI-013: the next press
    "pc3": ["pc 0 3", "sleep 1500", "pc 0 3"],                                          # MIDI-007: twice
    "ccbtn20": ["cc 0 20 127", "sleep 100", "cc 0 20 0"],                               # MIDI-008
    "note62": ["note 0 62 100", "sleep 150", "off 0 62"],                               # MIDI-008: Play/Pause
    "clock120": ["start", "clock 120 10"],                                              # MIDI-010
    "clock174": ["clock 174 10"],
    "clockstop": ["stop"],
    "feedback-move": ["sweep 0 21 0 127 3 40"],                                         # MIDI-009: the control moves
}


def build_helper() -> Path:
    if not HELPER.exists() or HELPER.stat().st_mtime < HELPER_SOURCE.stat().st_mtime:
        HELPER.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["xcrun", "swiftc", "-O", str(HELPER_SOURCE), "-o", str(HELPER)], check=True)
    return HELPER


def feedback_result(times: list[float], window_start: float, sends_end: float, now: float) -> dict:
    """MIDI-009: messages back during and after the moves. An echo loop keeps sending after the control stops;
    the app's feedback must go quiet within 1 s of the last move and stay bounded (at most one per move plus a few)."""
    inside = [t for t in times if t >= window_start]
    late = [t for t in inside if t > sends_end + 1.0]
    return {"received": len(inside), "afterTheMoves": len(late), "ok": len(inside) <= 60 and not late and now > sends_end}


class Helper:
    def __init__(self, path: Path):
        self.proc = subprocess.Popen([str(path)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        self.incoming: list[float] = []
        self.replies: list[str] = []
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self) -> None:
        assert self.proc.stdout is not None
        for line in self.proc.stdout:
            line = line.rstrip()
            if line.startswith("MIDI-IN "):
                self.incoming.append(time.time())
            else:
                self.replies.append(line)
                print(f"midi: {line}", flush=True)

    def command(self, line: str, timeout: float = 30) -> bool:
        if self.proc.poll() is not None:
            return False
        before = len(self.replies)
        assert self.proc.stdin is not None
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()
        end = time.time() + timeout
        while time.time() < end:
            for reply in self.replies[before:]:
                if reply.endswith(line):
                    return reply.startswith("OK")
            time.sleep(0.02)
        return False


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--log", required=True)
    p.add_argument("--host", required=True, help="the device's Bonjour name, e.g. iPhone77.local")
    p.add_argument("--port", type=int, default=5004)
    p.add_argument("--timeout", type=float, default=900)
    args = p.parse_args(argv)
    helper = Helper(build_helper())
    time.sleep(1)
    if helper.proc.poll() is not None:
        return 2   # the helper printed why (network session off)
    if not helper.command(f"connect {devices.resolve(args.host)} {args.port}"):
        return 2
    log, done, seen, failed = Path(args.log), time.monotonic() + args.timeout, 0, False
    try:
        while time.monotonic() < done:
            lines = log.read_text(errors="replace").splitlines() if log.exists() else []
            for line in lines[seen:]:
                if "MIDI-READY " in line:
                    scenario = line.split("MIDI-READY ", 1)[1].split()[0]
                    start = time.time()
                    ok = all(helper.command(c) for c in SCENARIOS.get(scenario, [f"unknown-{scenario}"]))
                    if scenario == "feedback-move":
                        sends_end = time.time()
                        time.sleep(3)
                        result = feedback_result(helper.incoming, start, sends_end, time.time())
                        ok = ok and result["ok"]
                        print(f"MIDI-FEEDBACK {json.dumps(result)}", flush=True)
                    failed |= not ok
                    print(f"midi: {scenario}: {'sent' if ok else 'FAILED'}", flush=True)
                if "** TEST" in line or "Testing failed" in line:
                    return 1 if failed else 0
            seen = len(lines)
            time.sleep(0.2)
        return 1
    finally:
        helper.command("quit", timeout=3)


if __name__ == "__main__":
    raise SystemExit(main())
