#!/usr/bin/env python3
"""QA-011 device automation: the Mac's side of a device test run (Batch 1; generalises osc_device_driver.py).

`follow` reads an xcodebuild log while the device tests run and answers each `MAC-DO {json}` line (printed by
`MacDriver.request` in Apps/projectM-iOS/DeviceUITests/SystemUI.swift) with an action from scripts/mac_driver/
(`audio.play`, `memory.warning`, `device.crashlogs`, … one module per batch). It prints `MAC-DONE <id> <seconds>
<result>` for each, to stdout and its own log. Tests never wait on this answer (the log reaches the Mac late): they
wait on an app probe.

`prompt-flow` runs the self-answering prompt batch (owner rule 14, amended 2026-11-18) on one device: uninstall the
app (a fresh install, so iOS asks every permission again), install the built app, copy the fixtures, then run
PromptFlowDeviceTests alone with `follow` beside it (and scripts/osc_device_driver.py with --osc-host), then, in a
second run, the tests that need its grants (AFTER_GRANTS). It runs alone, never inside another batch; every other run
passes
-skip-testing:projectM-iOSDeviceUITests/PromptFlowDeviceTests.

    python3 scripts/mac_device_driver.py follow --log <xcodebuild log> --device D1
    python3 scripts/mac_device_driver.py prompt-flow --device D1 [--osc-host iPhone77.local] [--dry-run]

Build first (docs/autotester.md): xcodebuild build-for-testing … -scheme DeviceAcceptance -derivedDataPath
Build/device-acceptance. Local network only; nothing leaves the LAN.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mac_driver  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DEVICES = {"D1": "iPhone15,4", "D2": "iPad17,3", "D3": "iPad15,7"}
PROMPT_FLOW = "projectM-iOSDeviceUITests/PromptFlowDeviceTests"
# Tests that need a grant only the prompt flow gives (testZ: every permission on). In an ordinary batch on an install
# without the grant they skip with the instruction; `prompt-flow` runs them right after the grants, in its own
# xcodebuild run (XCTest orders classes by name, so they cannot share the prompt flow's run). QA-011 2026-11-19.
AFTER_GRANTS = [
    "projectM-iOSDeviceUITests/B08RecordingDeviceTests/testREC004MicrophoneRecordingHasAnAudioTrackOnlyWithTheSetting",
]
END_MARKERS = ("** TEST EXECUTE SUCCEEDED **", "** TEST EXECUTE FAILED **", "** TEST FAILED **", "** TEST SUCCEEDED **",
               "Testing failed:")


def device_ids(listing: dict) -> dict[str, tuple[str, str]]:
    """D1-D3 → (devicectl identifier, hardware UDID for xcodebuild), from `devicectl list devices` JSON."""
    by_type = {}
    for d in listing.get("result", {}).get("devices", []):
        hw = d.get("hardwareProperties", {})
        by_type[hw.get("productType")] = (d.get("identifier", ""), hw.get("udid", ""))
    return {name: by_type[t] for name, t in DEVICES.items() if t in by_type}


def list_devices() -> dict:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "devices.json"
        subprocess.run(["xcrun", "devicectl", "list", "devices", "--json-output", str(out)], check=True,
                       capture_output=True)
        return json.loads(out.read_text())


def follow(log: Path, context: mac_driver.Context, timeout: float = 1800, out=print,
           stop: threading.Event | None = None, poll: float = 0.2) -> int:
    """Answers MAC-DO lines in `log` until the test run ends (its end marker), `stop` is set, or `timeout`."""
    seen, end = 0, time.monotonic() + timeout
    started = time.monotonic()
    try:
        while time.monotonic() < end and not (stop and stop.is_set()):
            lines = log.read_text(errors="replace").splitlines() if log.exists() else []
            for line in lines[seen:]:
                request = mac_driver.parse_request(line)
                if request is not None:
                    result = mac_driver.dispatch(request, context)
                    out(f"MAC-DONE {request.get('id', '?')} {time.monotonic() - started:.1f} "
                        f"{request['action']}: {result}")
                if any(marker in line for marker in END_MARKERS):
                    return 0
            seen = len(lines)
            time.sleep(poll)
        return 0 if stop and stop.is_set() else 1
    finally:
        context.cleanup()


def prompt_flow_commands(device: str, udid: str, derived: Path, app: Path, log_dir: Path,
                         osc: bool) -> list[list[str]]:
    """The fresh-install steps, the prompt-flow test command, then the after-grants command (the xcodebuild commands
    start with `env`), for running or printing."""
    env = ["TEST_RUNNER_MAC_DRIVER=1"] + (["TEST_RUNNER_OSC_DRIVER=1"] if osc else [])

    def xcodebuild(bundle: str, only: list[str]) -> list[str]:
        return ["env", *env, "xcodebuild", "test-without-building", "-project", "ProjectM-DeviceTests.xcodeproj",
                "-scheme", "DeviceAcceptance", "-destination", f"platform=iOS,id={udid}", "-derivedDataPath",
                str(derived), "-resultBundlePath", str(log_dir / bundle), *[f"-only-testing:{t}" for t in only],
                "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "300"]

    return [
        ["xcrun", "devicectl", "device", "uninstall", "app", "--device", device, mac_driver.BUNDLE],
        ["xcrun", "devicectl", "device", "install", "app", "--device", device, str(app)],
        [sys.executable, str(ROOT / "scripts" / "install_test_fixtures.py"), "--device-id", device, "--media"],
        xcodebuild("prompt-flow.xcresult", [PROMPT_FLOW]),
        xcodebuild("after-grants.xcresult", AFTER_GRANTS),
    ]


def run_prompt_flow(args: argparse.Namespace) -> int:
    derived = Path(args.derived)
    app = derived / "Build" / "Products" / "Debug-iphoneos" / "projectM-iOS.app"
    log_dir = ROOT / ".autonomous" / "logs" / f"prompt-flow-{args.device}-{time.strftime('%Y%m%d-%H%M%S')}"
    if args.dry_run:
        device, udid = f"<{args.device} devicectl id>", f"<{args.device} UDID>"
    else:
        ids = device_ids(list_devices())
        if args.device not in ids:
            print(f"mac_device_driver: {args.device} not found (paired and on the network?)")
            return 1
        device, udid = ids[args.device]
        if not app.exists():
            print(f"mac_device_driver: {app} missing: build-for-testing first (docs/autotester.md)")
            return 1
    commands = prompt_flow_commands(device, udid, derived, app, log_dir, bool(args.osc_host))
    if args.dry_run:
        for cmd in commands:
            print(" ".join(cmd))
        return 0
    log_dir.mkdir(parents=True, exist_ok=True)
    for cmd in (c for c in commands if c[0] != "env"):
        result = subprocess.run(cmd, capture_output=True, text=True)
        ok = result.returncode == 0 or cmd[3] == "uninstall"   # nothing to uninstall is fine
        print(f"mac_device_driver: {' '.join(cmd[:4])}: {'ok' if ok else 'FAILED ' + result.stderr.strip()[-300:]}")
        if not ok:
            return 1
    tests = [c for c in commands if c[0] == "env"]
    status = _run_tests(tests[0], log_dir, "xcodebuild", device, args, "prompt flow")
    # The after-grants tests run whatever the prompt flow's result: without the grant they skip and say why.
    after = _run_tests(tests[1], log_dir, "after-grants", device, args, "after-grants tests")
    print(f"mac_device_driver: logs in {log_dir.relative_to(ROOT)}")
    return status or after


def _run_tests(command: list[str], log_dir: Path, name: str, device: str, args: argparse.Namespace,
               what: str) -> int:
    """One xcodebuild test run with the Mac driver (and the OSC driver with --osc-host) following its log."""
    log = log_dir / f"{name}.log"
    driver_log = log_dir / f"mac-driver-{name}.log"
    stop = threading.Event()
    context = mac_driver.Context(device=device)
    with driver_log.open("w") as sink:
        def out(text: str) -> None:
            print(text, flush=True)
            sink.write(text + "\n")
            sink.flush()
        follower = threading.Thread(target=follow, args=(log, context), kwargs={"out": out, "stop": stop}, daemon=True)
        follower.start()
        osc = None
        if args.osc_host:
            osc = subprocess.Popen([sys.executable, str(ROOT / "scripts" / "osc_device_driver.py"), "--log", str(log),
                                    "--host", args.osc_host])
        with log.open("w") as handle:
            status = subprocess.run(command, cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT).returncode
        stop.set()
        follower.join(timeout=10)
        if osc is not None and osc.poll() is None:
            osc.terminate()
    text = log.read_text(errors="replace")
    executed = [line for line in text.splitlines() if line.strip().startswith("Executed ")]
    print(f"mac_device_driver: {what} on {args.device}: exit {status}; "
          f"{executed[-1].strip() if executed else 'no tests ran'}")
    return status


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="command", required=True)
    f = sub.add_parser("follow", help="answer MAC-DO lines in a running xcodebuild log")
    f.add_argument("--log", required=True, type=Path)
    f.add_argument("--device", choices=sorted(DEVICES), help="the device (for devicectl actions)")
    f.add_argument("--timeout", type=float, default=1800)
    f.add_argument("--dry-run", action="store_true", help="print the actions' commands instead of running them")
    pf = sub.add_parser("prompt-flow", help="fresh install, fixtures, then PromptFlowDeviceTests alone")
    pf.add_argument("--device", choices=sorted(DEVICES), required=True)
    pf.add_argument("--derived", default=str(ROOT / "Build" / "device-acceptance"))
    pf.add_argument("--osc-host", help="the device's Bonjour name: also run osc_device_driver.py (OSC-001-T26)")
    pf.add_argument("--dry-run", action="store_true", help="print the commands only")
    args = p.parse_args(argv)
    if args.command == "follow":
        device = None
        if args.device and not args.dry_run:
            device = device_ids(list_devices()).get(args.device, (None, None))[0]
        context = mac_driver.Context(device=device or (f"<{args.device}>" if args.device else None), dry_run=args.dry_run)
        return follow(args.log, context, args.timeout, out=lambda text: print(text, flush=True))
    return run_prompt_flow(args)


if __name__ == "__main__":
    raise SystemExit(main())
