#!/usr/bin/env python3
"""QA-011 Batch 8: runs one two-device test on D1 and D2 at once and coordinates them over the xcodebuild logs.

Each device runs from its own copy of the build products (autotester: parallel devices from one build), so one
run never disturbs the other. The role that waits starts first; the acting role starts when the first prints its
`PEER-READY <tag>` line. Each test gets the other device's address (`TEST_RUNNER_PEER_IP`) and the Mac's
(`TEST_RUNNER_MAC_IP`). Mac-side drivers follow the logs where a scenario needs them (OSC for OSC-008; no MIDI driver:
MIDI-012's import comes from the app's own DEBUG virtual MIDI source, 2026-11-21). Scenarios:

  osc008   D1 testOSC008AllowlistReceiver (+ osc_device_driver.py on D1), then D2 testOSC008AllowlistSender
  osc011   D2 testOSC011Announce, then D1 testOSC011Find
  osc012   D2 testOSC012Follow, then D1 testOSC012Lead; pairs D1's PEER-STEP with D2's PEER-SEEN lines and checks
           each cue lands on D2 within 0.5 s (device clocks: both NTP-synced; the offset is not corrected)
  midi012  D1 testMIDI012ProfileExport; copies "Profile 1.pmmidi" from D1's Documents to D2's; D2
           testMIDI012ProfileImport (CC 21 from the in-app virtual source, `-uitestVirtualMIDISource`)

Wi-Fi only; no USB-cable step (owner ruling 2026-11-18). Logs: Build/peer/<scenario>-<device>.log.

    python3 scripts/mac_driver/peer.py osc012 --products Build/device-acceptance/Build/Products [--dry-run]
"""
from __future__ import annotations

import argparse
import json
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from mac_driver import devices  # noqa: E402

UI = "projectM-iOSDeviceUITests"
PLANS: dict[str, dict] = {
    "osc008": {"first": ("D1", "B09OSCPeerDeviceTests/testOSC008AllowlistReceiver"), "ready": "osc008-receiver",
               "second": ("D2", "B09OSCPeerDeviceTests/testOSC008AllowlistSender"), "osc": "D1"},
    "osc011": {"first": ("D2", "B09OSCPeerDeviceTests/testOSC011Announce"), "ready": "osc011-announce",
               "second": ("D1", "B09OSCPeerDeviceTests/testOSC011Find")},
    "osc012": {"first": ("D2", "B09OSCPeerDeviceTests/testOSC012Follow"), "ready": "osc012-follow",
               "second": ("D1", "B09OSCPeerDeviceTests/testOSC012Lead"), "pair": True},
    "midi012": {"first": ("D1", "B10MIDIDeviceTests/testMIDI012ProfileExport"), "sequential": True,
                "copy": "Profile 1.pmmidi", "second": ("D2", "B10MIDIDeviceTests/testMIDI012ProfileImport")},
}


def xctestrun(products: Path) -> Path:
    runs = sorted(products.glob("*.xctestrun"))
    if not runs:
        raise SystemExit(f"no .xctestrun in {products}: run xcodebuild build-for-testing first")
    return runs[0]


def test_command(run: Path, udid: str, test: str, env: dict[str, str]) -> list[str]:
    # TEST_RUNNER_* values reach the test runner only through xcodebuild's environment, never as build-setting
    # arguments after test-without-building -xctestrun (2026-11-22: requireMac tests skipped with the driver running).
    return (["env"] + [f"TEST_RUNNER_{k}={v}" for k, v in sorted(env.items())]
            + ["xcodebuild", "test-without-building", "-xctestrun", str(run), "-destination", f"platform=iOS,id={udid}",
               f"-only-testing:{UI}/{test}", "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "300"])


def remap(plan: dict, mapping: dict[str, str]) -> dict:
    """The plan with each device named in `mapping` replaced (roles, the OSC driver's device)."""
    out = dict(plan)
    for key in ("first", "second"):
        device, test = plan[key]
        out[key] = (mapping.get(device, device), test)
    if plan.get("osc"):
        out["osc"] = mapping.get(plan["osc"], plan["osc"])
    if out["first"][0] == out["second"][0]:
        raise SystemExit(f"both roles on {out['first'][0]}: a peer test needs two devices")
    return out


def per_device_products(products: Path, device: str) -> Path:
    """A copy of the products for one device (rebuilt when the build is newer than the copy)."""
    copy = ROOT / "Build" / "peer" / device / "Products"
    stamp = max((p.stat().st_mtime for p in products.glob("*.xctestrun")), default=0)
    if not copy.exists() or min((p.stat().st_mtime for p in copy.glob("*.xctestrun")), default=0) < stamp:
        shutil.rmtree(copy, ignore_errors=True)
        shutil.copytree(products, copy, symlinks=True)
    return copy


def parse_marks(lines: list[str], kind: str) -> list[tuple[int, float]]:
    """`PEER-STEP cue=3 t=1763459000.12` (or PEER-SEEN) → [(3, 1763459000.12)]."""
    marks = []
    for line in lines:
        if f"PEER-{kind} " not in line:
            continue
        fields = dict(f.split("=", 1) for f in line.split(f"PEER-{kind} ", 1)[1].split() if "=" in f)
        try:
            marks.append((int(fields["cue"]), float(fields["t"])))
        except (KeyError, ValueError):
            continue
    return marks


def pair_latencies(steps: list[tuple[int, float]], seen: list[tuple[int, float]], limit: float = 0.5) -> dict:
    """Each lead step's cue matched with the follower's first change to that cue after it (OSC-012-T22)."""
    latencies = []
    for cue, t in steps:
        match = next((s for c, s in seen if c == cue and s >= t - 0.25), None)
        if match is not None:
            latencies.append(round(match - t, 3))
    return {"steps": len(steps), "matched": len(latencies),
            "median": statistics.median(latencies) if latencies else None,
            "max": max(latencies) if latencies else None,
            "ok": bool(latencies) and len(latencies) >= max(1, len(steps) - 1) and max(latencies) <= limit}


def wait_for(log: Path, needle: str, proc: subprocess.Popen, timeout: float) -> bool:
    end = time.time() + timeout
    while time.time() < end:
        if log.exists() and needle in log.read_text(errors="replace"):
            return True
        if proc.poll() is not None:
            return False
        time.sleep(0.5)
    return False


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("scenario", choices=sorted(PLANS))
    p.add_argument("--products", type=Path, default=ROOT / "Build" / "device-acceptance" / "Build" / "Products")
    p.add_argument("--dry-run", action="store_true", help="print the commands; run nothing")
    p.add_argument("--as", dest="remap", action="append", default=[], metavar="D1=D3",
                   help="give a role's device to another device (D1 is not used in QA-011: --as D1=D3 pairs D2 with D3)")
    args = p.parse_args(argv)
    plan = remap(PLANS[args.scenario], dict(r.split("=", 1) for r in args.remap))
    names = [plan["first"][0], plan["second"][0]]
    if args.dry_run:
        ids = {n: {"identifier": f"<{n} devicectl id>", "udid": f"<{n} UDID>"} for n in names}
        ips = {n: f"<{n} address>" for n in names}
        mac = "<Mac address>"
    else:
        ids = devices.identifiers()
        missing = [n for n in names if n not in ids]
        if missing:
            raise SystemExit(f"not paired or not reachable: {missing}")
        ips = {n: devices.resolve(devices.DEVICES[n]["host"]) for n in names}
        mac = devices.mac_address_toward(ips[names[0]])
    logs = {n: ROOT / "Build" / "peer" / f"{args.scenario}-{n}.log" for n in names}
    helpers: list[subprocess.Popen] = []

    def start(role: tuple[str, str]) -> subprocess.Popen | None:
        device, test = role
        other = names[1] if device == names[0] else names[0]
        products = args.products if args.dry_run else per_device_products(args.products, device)
        run = products / "<name>.xctestrun" if args.dry_run else xctestrun(products)
        cmd = test_command(run, ids[device]["udid"], test, {"PEER_IP": ips[other], "MAC_IP": mac})
        print(f"peer: {device}: {' '.join(cmd)}", flush=True)
        if args.dry_run:
            return None
        logs[device].parent.mkdir(parents=True, exist_ok=True)
        return subprocess.Popen(cmd, stdout=logs[device].open("w"), stderr=subprocess.STDOUT)

    def driver(script: list[str]) -> None:
        print(f"peer: driver: {' '.join(script)}", flush=True)
        if not args.dry_run:
            helpers.append(subprocess.Popen([sys.executable] + script))

    status = 0
    try:
        if plan.get("osc"):
            d = plan["osc"]
            driver([str(ROOT / "scripts" / "osc_device_driver.py"), "--log", str(logs[d]), "--host", devices.DEVICES[d]["host"]])
        first = start(plan["first"])
        if plan.get("sequential"):
            if first is not None:
                status |= first.wait()
            if plan.get("copy"):
                name = plan["copy"]
                print(f"peer: copy {name}: {names[0]} → {names[1]}", flush=True)
                if not args.dry_run:
                    with tempfile.TemporaryDirectory() as tmp:
                        local = devices.pull(ids[names[0]]["identifier"], name, Path(tmp) / name)
                        devices.push(ids[names[1]]["identifier"], local, name)
            second = start(plan["second"])
            if second is not None:
                status |= second.wait()
        else:
            if first is not None and not wait_for(logs[names[0]], f"PEER-READY {plan['ready']}", first, 300):
                print(f"peer: {names[0]} never printed PEER-READY {plan['ready']}", flush=True)
                first.terminate()
                return 1
            second = start(plan["second"])
            for proc in (first, second):
                if proc is not None:
                    status |= proc.wait()
        if plan.get("pair") and not args.dry_run:
            steps = parse_marks(logs[plan["second"][0]].read_text(errors="replace").splitlines(), "STEP")   # the lead
            seen = parse_marks(logs[plan["first"][0]].read_text(errors="replace").splitlines(), "SEEN")   # the follower
            result = pair_latencies(steps, seen)
            print(f"PEER-LATENCY {json.dumps(result)}", flush=True)
            status |= 0 if result["ok"] else 1
        for h in helpers:
            status |= h.wait(timeout=60)
    finally:
        for h in helpers:
            if h.poll() is None:
                h.terminate()
    verdict = "dry run, nothing ran" if args.dry_run else ("pass" if status == 0 else "FAIL")
    print(f"peer: {args.scenario}: {verdict} (logs: {', '.join(str(l) for l in logs.values())})")
    return 1 if status else 0


if __name__ == "__main__":
    raise SystemExit(main())
