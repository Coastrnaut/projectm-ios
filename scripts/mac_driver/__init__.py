"""Action modules for scripts/mac_device_driver.py (QA-011 device automation, Batch 1).

A device test prints `MAC-DO {"id": "<n>", "action": "<module>.<verb>", ...}` in the xcodebuild log; the driver
imports `mac_driver.<module>` and calls `ACTIONS[<verb>](request, context)`. Each batch adds its own module file
(audio, memory and device here; xctrace, osc, midi, peer from later batches) with an `ACTIONS` dict. An action returns
a short text for the driver's `MAC-DONE <id>` line and must not block for long: start long work in the background
and stop it from a later request (`audio.stop`) or when the run ends (`Context.cleanup`).
"""
from __future__ import annotations

import importlib
import json
import re
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

BUNDLE = "org.projectmios.ProjectMiOS"
_MODULE = re.compile(r"^[a-z][a-z0-9_]*$")


@dataclass
class Context:
    """What actions need: the devicectl identifier, a command runner (swapped in tests), background processes."""
    device: str | None = None
    bundle: str = BUNDLE
    dry_run: bool = False
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run
    popen: Callable[..., subprocess.Popen] = subprocess.Popen
    background: dict = field(default_factory=dict)
    log: list = field(default_factory=list)

    def command(self, cmd: list[str]) -> subprocess.CompletedProcess:
        self.log.append(" ".join(cmd))
        if self.dry_run:
            return subprocess.CompletedProcess(cmd, 0, "", "")
        return self.run(cmd, capture_output=True, text=True)

    def start(self, name: str, cmd: list[str]) -> None:
        """Starts `cmd` in the background under `name`, stopping an earlier one of that name."""
        self.stop(name)
        self.log.append(" ".join(cmd) + " &")
        if not self.dry_run:
            self.background[name] = self.popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def stop(self, name: str) -> bool:
        proc = self.background.pop(name, None)
        if proc is None:
            return False
        if proc.poll() is None:
            proc.terminate()
        return True

    def cleanup(self) -> None:
        for name in list(self.background):
            self.stop(name)

    def devicectl_json(self, args: list[str]) -> dict:
        """Runs `xcrun devicectl <args> --json-output <tmp>` and returns the parsed result ({} on failure)."""
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out.json"
            result = self.command(["xcrun", "devicectl", *args, "--json-output", str(out)])
            if result.returncode != 0 or not out.exists():
                return {}
            return json.loads(out.read_text())


def parse_request(line: str) -> dict | None:
    """The request in a log line holding `MAC-DO {json}`, or None."""
    if "MAC-DO " not in line:
        return None
    try:
        request = json.loads(line.split("MAC-DO ", 1)[1].strip())
    except json.JSONDecodeError:
        return None
    if not isinstance(request, dict) or "." not in str(request.get("action", "")):
        return None
    return request


def resolve(action: str) -> Callable[[dict, Context], str]:
    """The function for `<module>.<verb>`; only modules of this package (a plain lowercase name)."""
    module, _, verb = action.partition(".")
    if not _MODULE.match(module):
        raise KeyError(f"bad module name {module!r}")
    actions = getattr(importlib.import_module(f"{__name__}.{module}"), "ACTIONS", {})
    if verb not in actions:
        raise KeyError(f"no action {action}")
    return actions[verb]


def dispatch(request: dict, context: Context) -> str:
    try:
        return resolve(str(request["action"]))(request, context)
    except (KeyError, ImportError, ValueError, OSError) as error:
        return f"error: {error}"
