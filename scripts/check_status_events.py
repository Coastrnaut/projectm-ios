#!/usr/bin/env python3
"""ACC-011-R11 (contract C2 of specs/100-acc-011-captioned-status-events): capture and recording
status announcements go through the status-event router, never a direct post.

Flags `UIAccessibility.post` and `AccessibilityNotification` in the files of contract C2. In
AppCoordinator.swift a line naming one of the out-of-scope announcements (`onScopeChange`,
`nativeVisualUnavailableMessage`, `glowUnavailableMessage`) is allowed. Comments are ignored.

Run: python3 scripts/check_status_events.py  (exit 0 = OK, 1 = violations listed as path:line)
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Apps" / "projectM-iOS"
CHECKED = [
    "Coordinators/StatusEvents.swift",
    "Coordinators/AppCoordinator+StatusEvents.swift",
    "Coordinators/FrameCaptureCoordinator.swift",
    "Coordinators/VideoRecordingCoordinator.swift",
    "Coordinators/CaptureShareCoordinator.swift",
    "Coordinators/RouteCoordinator.swift",
    "Coordinators/SceneRepairCoordinator.swift",
    "Views/VisualizerView.swift",
    "Views/SourceStatusIndicator.swift",
    "Views/BackgroundNoticeView.swift",
    "Views/OSCListenerBadge.swift",
    "Views/SessionRecoveryOfferCard.swift",
    "Views/CameraIndicator.swift",
    "Views/CaptureResultPanels.swift",
    "Views/StatusCaptionView.swift",
]
COORDINATOR = "Coordinators/AppCoordinator.swift"
ALLOWED_IN_COORDINATOR = ("onScopeChange", "nativeVisualUnavailableMessage", "glowUnavailableMessage")
DIRECT = re.compile(r"\bUIAccessibility\s*\.\s*post\b|\bAccessibilityNotification\b")


def code_of(line: str) -> str:
    """The line without a trailing // comment (string literals blanked first)."""
    line = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    index = line.find("//")
    return line if index < 0 else line[:index]


def violations(text: str, allowed: tuple[str, ...] = ()) -> list[int]:
    """1-based line numbers of direct posts not excused by an allowed name on the same line."""
    found = []
    for number, line in enumerate(text.splitlines(), start=1):
        code = code_of(line)
        if DIRECT.search(code) and not any(name in code for name in allowed):
            found.append(number)
    return found


def check(app: Path = APP) -> list[str]:
    problems = []
    targets = [(name, ()) for name in CHECKED] + [(COORDINATOR, ALLOWED_IN_COORDINATOR)]
    for name, allowed in targets:
        path = app / name
        if not path.exists():
            problems.append(f"{name}: missing (contract C2 lists it)")
            continue
        for number in violations(path.read_text(encoding="utf-8"), allowed):
            problems.append(f"{name}:{number}: direct announcement post; use the status-event router (ACC-011-R3)")
    return problems


def main() -> int:
    problems = check()
    for problem in problems:
        print(problem)
    print("check_status_events: " + ("OK" if not problems else f"{len(problems)} violation(s)"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
