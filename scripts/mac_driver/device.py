"""Facts from the device for the record: `device.crashlogs` lists the app's crash reports since a time.

    MAC-DO {"action": "device.crashlogs", "bundle": "org.projectmios.ProjectMiOS", "since": 1794996000.0}

Used by PromptFlowDeviceTests' CAM-001-T25: iOS ends the app when a permission is revoked, which is a kill, not a
crash, so no report may appear. The answer goes to the driver's log, which is the evidence.
"""
from __future__ import annotations

from datetime import datetime


def crash_reports(listing: dict, name: str, since: float) -> list[str]:
    found = []
    for item in listing.get("result", {}).get("files", []):
        path = str(item.get("relativePath", item.get("name", "")))
        if name.lower() not in path.lower():
            continue
        stamp = item.get("lastModDate") or item.get("creationDate")
        when = None
        if isinstance(stamp, str):
            try:
                when = datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
            except ValueError:
                when = None
        if when is None or when >= since:
            found.append(path)
    return found


def crashlogs(request: dict, context) -> str:
    if not context.device:
        raise ValueError("no device (--device)")
    listing = context.devicectl_json(["device", "info", "files", "--device", context.device,
                                      "--domain-type", "systemCrashLogs"])
    reports = crash_reports(listing, "projectM", float(request.get("since", 0)))
    return f"crash reports: {len(reports)}" + (f" ({', '.join(reports)})" if reports else "")


ACTIONS = {"crashlogs": crashlogs}
