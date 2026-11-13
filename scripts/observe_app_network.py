#!/usr/bin/env python3
"""Observe an app's network activity on the iOS Simulator while a command runs (FILE-012-R6, R7). macOS only.

Simulator apps are Mac processes on the Mac's network stack, so the Mac can see them (research
FILE-012 D1, D2 in specs/076-file-012-no-telemetry-verification/plan.md). While `<command>` runs
(usually `xcodebuild test-without-building … -only-testing:…`), this script:

* finds every process of the app launched in the given simulator (`ps`; UI tests relaunch the app);
* samples their internet sockets every `--interval` seconds (`lsof -a -i -n -P -F`);
* records the simulator's Network-framework and URL-loading log events for the app's process
  (`xcrun simctl spawn <udid> log stream --style ndjson`), which keep even connections shorter than
  one sample;
* with `--probe` and `--expect osc:<port>`: once the app's UDP listener on the port appears, sends one
  OSC datagram to it from 127.0.0.1, proving the observer can see a peer socket and its connection.

Then it classifies what it saw:

* `--expect none`: any socket, and any log event except launch bookkeeping, is a violation;
* `--expect osc:<port>`: allowed are the UDP listener bound to the port, inbound peer sockets on that
  port from the probe, listener events and connections the log describes as server-side; anything
  else (an outbound socket, a client connection, a resolver or URL-loading event) is a violation.

It fails (exit 1) on a violation, when the command fails, or when it could not observe: no app process
seen, the log stream never became ready, or the requested probe was not seen in both layers.

    python3 scripts/observe_app_network.py --udid <udid> --executable projectM-iOS \\
        --expect none --report out.json -- xcodebuild test-without-building ...

The parsing and classification functions are pure and tested on any OS (scripts/test_scripts.py).
"""
from __future__ import annotations

import argparse
import json
import re
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

LOG_SUBSYSTEMS = '(subsystem BEGINSWITH "com.apple.network" OR subsystem BEGINSWITH "com.apple.CFNetwork")'
# Launch bookkeeping seen with no networking at all (plan D2): app-launch activity reports and the
# networking library reading its settings.
IGNORED_CATEGORIES = {"activity"}
IGNORED_MESSAGE_PREFIXES = ("networkd_settings_read_from_file_locked",)
LISTENER_EVENT = re.compile(r"\[L\d+\]|nw_listener|NWConcrete_nw_listener|SO_NECP_LISTENUUID")
CONNECTION_ID = re.compile(r"\[C(\d+)[\] ]")
OUTBOUND_EVENT = re.compile(r"nw_resolver|getaddrinfo|\bdns\b|Task <|NSURLSession|URLSession|"
                            r"nw_connection_create_with_id|, client[,\]]", re.I)
PROBE_PAYLOAD = b"/file012/probe\x00\x00,\x00\x00\x00"   # an OSC message no binding uses


# MARK: Pure functions

def parse_expect(value: str) -> int | None:
    """`none` → None; `osc:<port>` → port. ValueError otherwise."""
    if value == "none":
        return None
    match = re.fullmatch(r"osc:(\d{1,5})", value)
    if not match or not 0 < int(match.group(1)) < 65536:
        raise ValueError(f"--expect must be none or osc:<port>, not {value!r}")
    return int(match.group(1))


def app_pids_from_ps(output: str, udid: str, executable: str) -> list[int]:
    """PIDs of `<executable>.app/<executable>` installed in simulator `udid`, from `ps -axo pid=,command=`."""
    marker = f"/Devices/{udid}/data/Containers/Bundle/Application/"
    suffix = f"/{executable}.app/{executable}"
    pids: list[int] = []
    for line in output.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2 or not parts[0].isdigit():
            continue
        command = parts[1].split(" -", 1)[0].rstrip()   # drop launch arguments
        if marker in command and command.endswith(suffix):
            pids.append(int(parts[0]))
    return pids


def parse_lsof_fields(output: str) -> list[dict]:
    """Sockets from `lsof -F pftPn` output: [{pid, fd, type, protocol, name}]."""
    sockets: list[dict] = []
    pid = 0
    current: dict | None = None
    for line in output.splitlines():
        if not line:
            continue
        tag, value = line[0], line[1:]
        if tag == "p":
            pid = int(value)
        elif tag == "f":
            current = {"pid": pid, "fd": value, "type": "", "protocol": "", "name": ""}
            sockets.append(current)
        elif current is not None and tag == "t":
            current["type"] = value
        elif current is not None and tag == "P":
            current["protocol"] = value
        elif current is not None and tag == "n":
            current["name"] = value
    return sockets


def split_endpoint(text: str) -> tuple[str, int | None]:
    host, _, port = text.rpartition(":")
    return host, int(port) if port.isdigit() else None


def classify_socket(sock: dict, osc_port: int | None, probe_ports: set[int]) -> tuple[str, bool]:
    """(description, allowed) for one socket."""
    name, protocol = sock.get("name", ""), sock.get("protocol", "")
    label = f"pid {sock.get('pid')} {protocol} {name}"
    if osc_port is None:
        return (f"{label}: no socket is expected with OSC off", False)
    if protocol != "UDP":
        return (f"{label}: only UDP is expected for OSC", False)
    local, arrow, remote = name.partition("->")
    _, local_port = split_endpoint(local)
    if local_port != osc_port:
        return (f"{label}: not bound to the OSC port {osc_port} (outbound or unexpected)", False)
    if not arrow:
        return (f"{label}: the OSC listener", True)
    remote_host, remote_port = split_endpoint(remote)
    if remote_host in ("127.0.0.1", "[::1]", "::1") and remote_port in probe_ports:
        return (f"{label}: inbound peer = the observer's probe", True)
    return (f"{label}: inbound peer that is not the probe", False)


def classify_log_events(events: list[dict], osc_port: int | None) -> dict:
    """Counts and violations for the app's network log events (dicts with category and eventMessage)."""
    relevant = [e for e in events
                if e.get("category", "") not in IGNORED_CATEGORIES
                and not str(e.get("eventMessage", "")).startswith(IGNORED_MESSAGE_PREFIXES)]
    result = {"events": len(events), "relevant": len(relevant), "listenerEvents": 0,
              "serverConnections": [], "violations": []}
    if osc_port is None:
        result["violations"] = [str(e.get("eventMessage", ""))[:200] for e in relevant]
        return result
    server: set[str] = set()
    seen: set[str] = set()
    for event in relevant:
        message = str(event.get("eventMessage", ""))
        if OUTBOUND_EVENT.search(message):
            result["violations"].append(message[:200])
            continue
        if LISTENER_EVENT.search(message) or event.get("category") == "listener":
            result["listenerEvents"] += 1
        for cid in CONNECTION_ID.findall(message):
            seen.add(cid)
            if ", server," in message or "udp, server" in message:
                server.add(cid)
    unproven = sorted(seen - server, key=int)
    result["violations"] += [f"connection C{cid} was never described as server-side (inbound)" for cid in unproven]
    result["serverConnections"] = sorted(server, key=int)
    return result


def evaluate(*, command_status: int, pids: list[int], log_ready: bool, sockets: list[dict], events: list[dict],
             osc_port: int | None, probe: bool, probe_ports: set[int]) -> dict:
    """The report's verdict from everything observed."""
    problems: list[str] = []
    if command_status != 0:
        problems.append(f"the observed command failed (exit {command_status})")
    if not pids:
        problems.append("blind: no app process was seen in the simulator")
    if not log_ready:
        problems.append("blind: the simulator log stream never became ready")
    unique: dict[tuple, dict] = {}
    for sock in sockets:
        unique.setdefault((sock.get("pid"), sock.get("protocol"), sock.get("name")), sock)
    socket_verdicts = [classify_socket(s, osc_port, probe_ports) for s in unique.values()]
    problems += [text for text, allowed in socket_verdicts if not allowed]
    logs = classify_log_events(events, osc_port)
    problems += [f"log: {v}" for v in logs["violations"]]
    if osc_port is not None:
        if not any(allowed and text.endswith("the OSC listener") for text, allowed in socket_verdicts):
            problems.append(f"the OSC listener on port {osc_port} was never seen")
        if probe:
            if not probe_ports:
                problems.append("blind: the probe was never sent")
            elif not any(allowed and "probe" in text for text, allowed in socket_verdicts):
                problems.append("blind: the probe's peer socket was not seen in lsof")
            if not logs["serverConnections"]:
                problems.append("blind: no server-side connection event for the probe in the log")
    return {"ok": not problems, "problems": problems, "processes": sorted(set(pids)),
            "sockets": [{"socket": text, "allowed": allowed} for text, allowed in socket_verdicts],
            "log": logs}


# MARK: Observation (macOS)

class Observer:
    def __init__(self, udid: str, executable: str, interval: float, osc_port: int | None, probe: bool) -> None:
        self.udid, self.executable, self.interval = udid, executable, interval
        self.osc_port, self.probe = osc_port, probe
        self.pids: set[int] = set()
        self.sockets: list[dict] = []
        self.samples = 0
        self.probe_ports: set[int] = set()
        self.events: list[dict] = []
        self.log_ready = threading.Event()
        self.stop = threading.Event()
        self.stream: subprocess.Popen | None = None

    def start_log(self) -> None:
        predicate = f'process == "{self.executable}" AND {LOG_SUBSYSTEMS}'
        self.stream = subprocess.Popen(
            ["xcrun", "simctl", "spawn", self.udid, "log", "stream", "--style", "ndjson", "--level", "debug",
             "--predicate", predicate], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        threading.Thread(target=self.read_log, daemon=True).start()

    def read_log(self) -> None:
        assert self.stream is not None and self.stream.stdout is not None
        for line in self.stream.stdout:
            if line.startswith("Filtering the log data"):
                self.log_ready.set()
                continue
            if not line.startswith("{"):
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            self.log_ready.set()
            self.events.append({key: event.get(key) for key in
                                ("timestamp", "processID", "subsystem", "category", "eventMessage")})

    def send_probe(self) -> None:
        sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sender.bind(("127.0.0.1", 0))
            sender.sendto(PROBE_PAYLOAD, ("127.0.0.1", self.osc_port))
            self.probe_ports.add(sender.getsockname()[1])
        finally:
            sender.close()

    def sample_loop(self) -> None:
        while not self.stop.is_set():
            listing = subprocess.run(["ps", "-axo", "pid=,command="], capture_output=True, text=True).stdout
            pids = app_pids_from_ps(listing, self.udid, self.executable)
            self.pids.update(pids)
            if pids:
                output = subprocess.run(["lsof", "-a", "-i", "-n", "-P", "-F", "pftPn", "-p",
                                         ",".join(str(p) for p in pids)], capture_output=True, text=True).stdout
                found = parse_lsof_fields(output)
                self.sockets += found
                self.samples += 1
                if self.probe and self.osc_port and not self.probe_ports and any(
                        s["protocol"] == "UDP" and s["name"].endswith(f":{self.osc_port}") and "->" not in s["name"]
                        for s in found):
                    time.sleep(0.3)   # let the listener finish starting before the datagram
                    self.send_probe()
            self.stop.wait(self.interval)

    def finish(self) -> None:
        self.stop.set()
        time.sleep(1.0)   # late log lines
        if self.stream:
            self.stream.terminate()
            try:
                self.stream.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.stream.kill()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Observe an app's network activity on the simulator (FILE-012)")
    parser.add_argument("--udid", required=True)
    parser.add_argument("--executable", required=True)
    parser.add_argument("--expect", required=True, help="none or osc:<port>")
    parser.add_argument("--probe", action="store_true", help="send one probe datagram to the OSC listener")
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--interval", type=float, default=0.2)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    osc_port = parse_expect(args.expect)
    if not command:
        parser.error("give the command to observe after --")
    if args.probe and osc_port is None:
        parser.error("--probe needs --expect osc:<port>")
    if sys.platform != "darwin":
        print("observe_app_network: macOS only (needs simctl, ps, lsof)")
        return 2

    observer = Observer(args.udid, args.executable, args.interval, osc_port, args.probe)
    observer.start_log()
    observer.log_ready.wait(timeout=20)
    sampler = threading.Thread(target=observer.sample_loop, daemon=True)
    sampler.start()
    started = time.monotonic()
    status = subprocess.run(command).returncode
    observer.finish()
    sampler.join(timeout=5)
    report = evaluate(command_status=status, pids=sorted(observer.pids), log_ready=observer.log_ready.is_set(),
                      sockets=observer.sockets, events=observer.events, osc_port=osc_port, probe=args.probe,
                      probe_ports=observer.probe_ports)
    report.update({"udid": args.udid, "executable": args.executable, "expect": args.expect,
                   "intervalSeconds": args.interval, "samples": observer.samples,
                   "durationSeconds": round(time.monotonic() - started, 1), "probePorts": sorted(observer.probe_ports),
                   "logEvents": observer.events})
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(f"observe_app_network: {len(report['processes'])} app process(es), {observer.samples} samples, "
          f"{len(report['sockets'])} distinct socket(s), {report['log']['events']} log event(s) "
          f"({report['log']['relevant']} relevant), probe ports {sorted(observer.probe_ports) or '-'}")
    for entry in report["sockets"]:
        print(f"  socket: {entry['socket']} ({'allowed' if entry['allowed'] else 'VIOLATION'})")
    for problem in report["problems"]:
        print(f"error: {problem}")
    print("observe_app_network: " + ("OK" if report["ok"] else f"{len(report['problems'])} problem(s)"))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
