#!/usr/bin/env python3
"""Final device-test gate (AUTO-013).

The physical-device suite may start only when every feature is in a terminal implementation
state and none of the feasible ones is blocked ("strict implementation completion"). When it
may start, the connected inventory is compared with D1-D3; a missing device leaves the run at
`awaiting_final_device` with the exact prerequisites. Nothing here records a pass.
"""
from __future__ import annotations

import json
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

try:
    from .scheduler import BLOCKED_STATES, DONE_STATES
except ImportError:
    from scheduler import BLOCKED_STATES, DONE_STATES

# docs/test-reports/devices.md (T017): product type -> device alias.
INVENTORY = {"iPhone15,4": "D1", "iPad17,3": "D2", "iPad15,7": "D3"}
PRESERVED_OS = {"D3": "26.5"}   # CLAUDE.md: keep the iPad A16 on iPadOS 26.5


@dataclass
class DeviceGateDecision:
    may_start: bool
    reasons: list[str] = field(default_factory=list)       # why not, when may_start is False
    pending: list[str] = field(default_factory=list)       # features not yet terminal
    blocked: list[str] = field(default_factory=list)       # feasible features that are blocked
    infeasible: list[str] = field(default_factory=list)    # excluded with a recorded reason


def implementation_decision(states: dict[str, str]) -> DeviceGateDecision:
    pending = sorted(f for f, s in states.items()
                     if s not in DONE_STATES and s not in BLOCKED_STATES)
    blocked = sorted(f for f, s in states.items() if s == "blocked")
    infeasible = sorted(f for f, s in states.items() if s == "infeasible")
    reasons = []
    if pending:
        reasons.append(f"{len(pending)} features are not implemented yet "
                       f"(first: {', '.join(pending[:5])})")
    if blocked:
        reasons.append(f"{len(blocked)} feasible features are blocked "
                       f"(first: {', '.join(blocked[:5])}); strict completion allows none")
    return DeviceGateDecision(not reasons, reasons, pending, blocked, infeasible)


def parse_devices(payload: dict) -> dict[str, dict]:
    """devicectl `list devices --json-output` -> alias -> {udid, identifier, os, state}."""
    found: dict[str, dict] = {}
    for device in payload.get("result", {}).get("devices", []):
        hardware = device.get("hardwareProperties", {})
        if hardware.get("reality") == "simulated":
            continue
        alias = INVENTORY.get(hardware.get("productType"))
        if not alias:
            continue
        connection = device.get("connectionProperties", {})
        found[alias] = {
            "identifier": device.get("identifier"), "udid": hardware.get("udid"),
            "os": device.get("deviceProperties", {}).get("osVersionNumber"),
            "os_build": device.get("deviceProperties", {}).get("osBuildUpdate"),
            "paired": connection.get("pairingState") == "paired",
            "tunnel": connection.get("tunnelState"),
        }
    return found


def list_devices(runner=subprocess.run) -> dict[str, dict]:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "devices.json"
        proc = runner(["xcrun", "devicectl", "list", "devices", "--json-output", str(out)],
                      capture_output=True, text=True, timeout=120)
        if proc.returncode != 0 or not out.exists():
            return {}
        return parse_devices(json.loads(out.read_text(encoding="utf-8")))


def device_prerequisites(devices: dict[str, dict]) -> list[str]:
    """What the owner must do before the suite can run on all of D1-D3. Empty when ready."""
    todo = []
    for alias in ("D1", "D2", "D3"):
        info = devices.get(alias)
        if not info:
            todo.append(f"{alias}: not visible to devicectl; connect it, unlock it and trust "
                        "this Mac")
            continue
        if not info.get("paired"):
            todo.append(f"{alias}: not paired; accept the trust prompt on the device")
        wanted = PRESERVED_OS.get(alias)
        if wanted and info.get("os") and not str(info["os"]).startswith(wanted):
            todo.append(f"{alias}: reports OS {info['os']}, expected {wanted} (the preserved "
                        "iPadOS 26 device must not be updated)")
    return todo


def decide(states: dict[str, str], devices: dict[str, dict] | None = None) -> dict:
    """The gate's full verdict, ready to store in the run state and the report."""
    impl = implementation_decision(states)
    verdict = {"implementation_complete": impl.may_start, "reasons": impl.reasons,
               "pending": impl.pending, "blocked": impl.blocked,
               "infeasible": impl.infeasible, "phase": "implementation",
               "device_prerequisites": []}
    if not impl.may_start:
        return verdict
    todo = device_prerequisites(devices or {})
    verdict["device_prerequisites"] = todo
    verdict["phase"] = "awaiting_final_device" if todo else "final_device"
    return verdict
