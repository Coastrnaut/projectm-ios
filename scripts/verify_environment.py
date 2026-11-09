#!/usr/bin/env python3
"""Check the build toolchain against the pins in ADR-0002 (task T004).

On non-macOS hosts this prints "macOS required for build tasks" and exits 0, because
Windows is used only for specification, documentation, and source authoring.

On macOS it exits 1 when a pinned tool is missing or its version does not match. While the
ADR still lists a pin as `TBD` (before Gate 0 / task T010), that tool is reported as
"unpinned" and the script exits 1, so CI cannot pass on an unpinned toolchain.
The Xcode build, written in the ADR as Xcode `27.2` (build 27B52), must also match the
"Build version" line of `xcodebuild -version` exactly (ADR-0002 owner ruling 5).
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


XCODE_BUILD_CMD = ["xcodebuild", "-version"]
XCODE_BUILD_PATTERN = r"Build version\s+(\S+)"


def pin_block(text: str | None = None) -> str:
    """The ADR-0002 "Toolchain pin" paragraph ("" when the ADR has none)."""
    if text is None:
        text = ADR.read_text(encoding="utf-8")
    line = next((l for l in text.splitlines() if "Toolchain pin" in l), "")
    return line + "\n" + text.split(line, 1)[1].split("\n\n", 1)[0] if line else ""


def read_pins(text: str | None = None) -> dict[str, str]:
    block = pin_block(text)
    return {name: m.group(1) for name in TOOLS
            if (m := re.search(rf"{name}\s+`([^`]+)`", block))}


def read_build_pin(text: str | None = None) -> str | None:
    """The Xcode build pinned as Xcode `27.2` (build 27B52) (ADR-0002 owner ruling 5), or None."""
    m = re.search(r"Xcode\s+`[^`]+`\s*\(build\s+([0-9A-Za-z]+)\)", pin_block(text))
    return m.group(1) if m else None


def check_build(pin: str | None, found: str | None) -> tuple[bool, str]:
    """Compare the pinned Xcode build with the one `xcodebuild -version` reports."""
    if pin is None:
        return False, f"Xcode build: unpinned in ADR-0002 (found {found or 'missing'})"
    if found is None:
        return False, f"Xcode build: missing (pinned {pin})"
    if found != pin:
        return False, f"Xcode build: {found} does not match pin {pin} (ADR-0002 Toolchain pin)"
    return True, f"Xcode build: {found} OK"


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
    ok, message = check_build(read_build_pin(), tool_version(XCODE_BUILD_CMD, XCODE_BUILD_PATTERN))
    print(message)
    if not ok:
        failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
