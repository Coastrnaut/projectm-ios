#!/usr/bin/env python3
"""ACC-001-R7 (contract C1): app UI animation goes through MotionPolicy.

Flags `withAnimation(`, `.animation(` and `UIView.animate` in Apps/projectM-iOS Swift sources
(tests excluded) unless the same line contains `reduceMotionAware(` or `MotionPolicy.` (a decorative
animation through the policy, or a safety fade marked `MotionPolicy.safetyFade`). MotionPolicy.swift
itself is exempt. Comments and string literals are ignored.

Run: python3 scripts/check_motion_policy.py  (exit 0 = OK, 1 = violations listed as path:line)
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Apps" / "projectM-iOS"
EXEMPT_FILES = {"MotionPolicy.swift"}
EXCLUDED_DIRS = {"Tests", "UITests"}
ANIMATION = re.compile(r"\bwithAnimation\s*[({]|\.animation\s*\(|\bUIView\s*\.\s*animate\b")
POLICY = re.compile(r"\breduceMotionAware\s*\(|\bMotionPolicy\s*\.")


def strip_line(line: str) -> str:
    """The line without string literals and a trailing // comment."""
    line = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    index = line.find("//")
    return line if index < 0 else line[:index]


def violations(text: str) -> list[int]:
    """1-based line numbers of animations that bypass the policy."""
    found: list[int] = []
    in_block = False
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw
        if in_block:
            end = line.find("*/")
            if end < 0:
                continue
            line, in_block = line[end + 2:], False
        while "/*" in line:
            start = line.find("/*")
            end = line.find("*/", start + 2)
            if end < 0:
                line, in_block = line[:start], True
                break
            line = line[:start] + line[end + 2:]
        code = strip_line(line)
        if ANIMATION.search(code) and not POLICY.search(code):
            found.append(number)
    return found


def source_files(app: Path = APP) -> list[Path]:
    return sorted(p for p in app.rglob("*.swift")
                  if p.name not in EXEMPT_FILES and not (EXCLUDED_DIRS & set(p.relative_to(app).parts)))


def check(app: Path = APP) -> list[str]:
    problems = []
    for path in source_files(app):
        for number in violations(path.read_text(encoding="utf-8")):
            problems.append(f"{path.relative_to(ROOT) if path.is_relative_to(ROOT) else path}:{number}: "
                            "animation bypasses MotionPolicy (use reduceMotionAware or MotionPolicy.safetyFade)")
    return problems


def main() -> int:
    problems = check()
    for problem in problems:
        print(problem)
    print("check_motion_policy: " + ("OK" if not problems else f"{len(problems)} violation(s)"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
