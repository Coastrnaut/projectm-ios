#!/usr/bin/env python3
"""Check the build toolchain against the pins in ADR-0002 (task T004).

On non-macOS hosts this prints "macOS required for build tasks" and exits 0, because
Windows is used only for specification, documentation, and source authoring.

On macOS it exits 1 when a pinned tool is missing or its version does not match. While the
ADR still lists a pin as `TBD` (before Gate 0 / task T010), that tool is reported as
"unpinned" and the script exits 1, so CI cannot pass on an unpinned toolchain.
"""
from __future__ import annotations

import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADR = ROOT / "docs" / "adr" / "0002-minimum-ios-version.md"
MIN_PYTHON = (3, 10)

# tool name in ADR -> (command, regex extracting the version from its output)
TOOLS: dict[str, tuple[list[str], str]] = {
    "Xcode": (["xcodebuild", "-version"], r"Xcode\s+([\d.]+)"),
    "SDK": (["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], r"([\d.]+)"),
    "Swift": (["swift", "--version"], r"Swift version\s+([\d.]+)"),
    "XcodeGen": (["xcodegen", "--version"], r"([\d.]+)"),
    "CMake": (["cmake", "--version"], r"cmake version\s+([\d.]+)"),
}


def read_pins() -> dict[str, str]:
    text = ADR.read_text(encoding="utf-8")
    line = next((l for l in text.splitlines() if "Toolchain pin" in l), "")
    block = line + "\n" + text.split(line, 1)[1].split("\n\n", 1)[0] if line else ""
    return {name: m.group(1) for name in TOOLS
            if (m := re.search(rf"{name}\s+`([^`]+)`", block))}


def tool_version(cmd: list[str], pattern: str) -> str | None:
    if shutil.which(cmd[0]) is None:
        return None
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    match = re.search(pattern, out)
    return match.group(1) if match else None


def main() -> int:
    if sys.version_info < MIN_PYTHON:
        print(f"Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ required, found {platform.python_version()}")
        return 1
    if platform.system() != "Darwin":
        print("macOS required for build tasks (this host is "
              f"{platform.system()}); documentation and script tasks only.")
        return 0

    pins = read_pins()
    failures = 0
    for name, (cmd, pattern) in TOOLS.items():
        pin = pins.get(name, "TBD")
        found = tool_version(cmd, pattern)
        if pin == "TBD":
            print(f"{name}: unpinned in ADR-0002 (found {found or 'missing'})")
            failures += 1
        elif found is None:
            print(f"{name}: missing (pinned {pin})")
            failures += 1
        elif not found.startswith(pin):
            print(f"{name}: {found} does not match pin {pin}")
            failures += 1
        else:
            print(f"{name}: {found} OK")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
