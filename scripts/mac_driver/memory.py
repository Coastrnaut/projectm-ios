"""A real memory warning to the app on the device: `memory.warning` (devicectl sendMemoryWarning).

    MAC-DO {"action": "memory.warning"}

The app's pid comes from `devicectl device info processes` (the process whose executable is inside the app bundle).
"""
from __future__ import annotations


def app_pid(processes: dict, executable: str = "projectM-iOS.app/projectM-iOS") -> int | None:
    for proc in processes.get("result", {}).get("runningProcesses", []):
        if str(proc.get("executable", "")).endswith(executable):
            return int(proc["processIdentifier"])
    return None


def warning(request: dict, context) -> str:
    if not context.device:
        raise ValueError("no device (--device)")
    pid = app_pid(context.devicectl_json(["device", "info", "processes", "--device", context.device]))
    if pid is None and not context.dry_run:
        raise ValueError("the app is not running on the device")
    result = context.command(["xcrun", "devicectl", "device", "process", "sendMemoryWarning", "--device",
                              context.device, "--pid", str(pid or 0)])
    return f"memory warning to pid {pid}" if result.returncode == 0 else f"error: {result.stderr.strip()[-200:]}"


ACTIONS = {"warning": warning}
