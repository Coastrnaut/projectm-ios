#!/usr/bin/env python3
"""Host-side check of a CaptureLab diagnostics export (task T039; used after CaptureLabUITests).

CaptureLabUITests.testBackgroundForegroundAreExported drives In-App Playback through background,
foreground and Export on a simulator, but XCUITest cannot read the app's files. This script reads
the export the test wrote and checks the lifecycle events in it:

  * the file is a CaptureLab export with schemaVersion 1;
  * it prints sourceMode, finalState and lifecycleEvents;
  * every lifecycleEvents[].atSeconds is a non-negative number and the times never decrease;
  * the expected events (default: background, foreground) appear in that order, possibly with
    other events in between.

Usage:
  python3 scripts/check_capturelab_export.py --udid <simulator UDID>
  python3 scripts/check_capturelab_export.py --json path/to/CaptureLab-20261108-184934.json
  python3 scripts/check_capturelab_export.py --udid <UDID> --expect background,foreground

With --udid the newest CaptureLab-*.json is taken from the tmp folder of CaptureLab's data
container, found under ~/Library/Developer/CoreSimulator/Devices/<udid>/data/Containers/Data/
Application/*/ by the container's metadata (bundle identifier org.projectmios.CaptureLab). The
simulator may be shut down. "Newest" means the latest file name (names carry the UTC export time),
then the latest modification time.

This checks lifecycle wiring only, not audio: a simulator export is never capture evidence
(Constitution X), and FR-031 evidence needs a device export showing non-silent audio.
Exit 0 when the checks pass, 1 when a check fails, 2 when no export can be found or read.
Standard library only.
"""
from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
from pathlib import Path

BUNDLE_ID = "org.projectmios.CaptureLab"
DEVICES_ROOT = Path.home() / "Library" / "Developer" / "CoreSimulator" / "Devices"
METADATA_PLIST = ".com.apple.mobile_container_manager.metadata.plist"
EXPORT_GLOB = "CaptureLab-*.json"
DEFAULT_EXPECT = ("background", "foreground")
UDID_RE = re.compile(r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")


class ExportNotFound(Exception):
    """No export file could be located or read (exit 2)."""


def container_bundle_id(container: Path) -> str | None:
    try:
        with (container / METADATA_PLIST).open("rb") as f:
            value = plistlib.load(f).get("MCMMetadataIdentifier")
    except (OSError, plistlib.InvalidFileException, ValueError):
        return None
    return value if isinstance(value, str) else None


def app_containers(udid: str, devices_root: Path = DEVICES_ROOT, bundle_id: str = BUNDLE_ID) -> list[Path]:
    """CaptureLab's data containers on the simulator `udid` (booted or shut down)."""
    if not UDID_RE.match(udid):
        raise ExportNotFound(f"not a simulator UDID: {udid!r}")
    apps = devices_root / udid / "data" / "Containers" / "Data" / "Application"
    if not apps.is_dir():
        raise ExportNotFound(f"no app data containers for simulator {udid} under {devices_root}")
    return sorted(c for c in apps.iterdir() if c.is_dir() and container_bundle_id(c) == bundle_id)


def newest_export(udid: str, devices_root: Path = DEVICES_ROOT, bundle_id: str = BUNDLE_ID) -> Path:
    containers = app_containers(udid, devices_root, bundle_id)
    if not containers:
        raise ExportNotFound(f"{bundle_id} has no data container on simulator {udid} (not installed?)")
    exports = [p for c in containers for p in (c / "tmp").glob(EXPORT_GLOB) if p.is_file()]
    if not exports:
        raise ExportNotFound(f"no {EXPORT_GLOB} in the tmp folder of {bundle_id} on simulator {udid}")
    return max(exports, key=lambda p: (p.name, p.stat().st_mtime))


def load_export(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as e:
        raise ExportNotFound(f"cannot read {path}: {e}") from e
    if not isinstance(data, dict):
        raise ExportNotFound(f"{path} is not a JSON object")
    return data


def check_export(data: dict, expect: tuple[str, ...] = DEFAULT_EXPECT) -> list[str]:
    """Returns a list of problems; empty when the export passes."""
    problems: list[str] = []
    if data.get("schemaVersion") != 1:
        problems.append(f"schemaVersion is {data.get('schemaVersion')!r}, expected 1")
    session = data.get("session")
    if not isinstance(session, dict):
        return problems + ["missing session object"]
    events = session.get("lifecycleEvents")
    if not isinstance(events, list):
        return problems + ["session.lifecycleEvents is missing or not a list"]

    names: list[str] = []
    previous: float | None = None
    for i, item in enumerate(events):
        if not isinstance(item, dict):
            problems.append(f"lifecycleEvents[{i}] is not an object")
            continue
        name, at = item.get("event"), item.get("atSeconds")
        names.append(name if isinstance(name, str) else repr(name))
        if isinstance(at, bool) or not isinstance(at, (int, float)) or at < 0:
            problems.append(f"lifecycleEvents[{i}].atSeconds is {at!r}, expected a number >= 0")
            continue
        if previous is not None and at < previous:
            problems.append(f"lifecycleEvents[{i}] ({name}) at {at} s is earlier than the previous event at {previous} s")
        previous = at

    position = 0
    for wanted in expect:
        try:
            position = names.index(wanted, position) + 1
        except ValueError:
            problems.append(f"expected events {list(expect)} in order; got {names}")
            break
    return problems


def describe(data: dict) -> list[str]:
    session = data.get("session") if isinstance(data.get("session"), dict) else {}
    lines = [
        f"schemaVersion: {data.get('schemaVersion')!r}",
        f"sourceMode: {session.get('sourceMode')!r}",
        f"finalState: {session.get('finalState')!r}",
        "lifecycleEvents:",
    ]
    events = session.get("lifecycleEvents")
    if isinstance(events, list) and events:
        for item in events:
            if isinstance(item, dict):
                lines.append(f"  {item.get('atSeconds')!r:>22} s  {item.get('event')}")
            else:
                lines.append(f"  {item!r}")
    else:
        lines.append("  (none)")
    return lines


def parse_expect(value: str) -> tuple[str, ...]:
    events = tuple(e.strip() for e in value.split(",") if e.strip())
    if not events:
        raise argparse.ArgumentTypeError("--expect needs at least one event name")
    return events


def main(argv: list[str] | None = None, devices_root: Path = DEVICES_ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--udid", help="simulator UDID; reads the newest export from CaptureLab's tmp folder")
    source.add_argument("--json", type=Path, help="path to a CaptureLab-*.json export")
    parser.add_argument("--expect", type=parse_expect, default=DEFAULT_EXPECT,
                        help="comma-separated lifecycle events that must appear in this order "
                             "(default: background,foreground)")
    args = parser.parse_args(argv)

    try:
        path = args.json if args.json is not None else newest_export(args.udid, devices_root)
        data = load_export(path)
    except ExportNotFound as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    print(f"export: {path}")
    for line in describe(data):
        print(line)
    problems = check_export(data, args.expect)
    if problems:
        for p in problems:
            print(f"FAIL: {p}", file=sys.stderr)
        return 1
    print(f"OK: {', '.join(args.expect)} in order with non-decreasing times (lifecycle check only)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
