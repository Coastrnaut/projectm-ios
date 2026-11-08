#!/usr/bin/env python3
"""Validate cross-references in the specification documents (task T003).

Fails (exit 1) when:
  * a FR-/SC-/RI- identifier cited anywhere under specs/ or docs/ is not defined in the
    feature spec, or an R-xx identifier is not defined in research.md;
  * contracts/diagnostics-export.schema.json is not valid JSON.

Files under scripts/fixtures/ are excluded from the normal scan. Pass --include-fixtures
(used by tests) to scan them too, which must then fail.

Runs on Windows and macOS (standard library only).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FEATURE = ROOT / "specs" / "001-ios-projectm-visualizer"
SPEC = FEATURE / "spec.md"
RESEARCH = FEATURE / "research.md"
SCHEMA = FEATURE / "contracts" / "diagnostics-export.schema.json"
FIXTURES = ROOT / "scripts" / "fixtures"


def defined_ids() -> dict[str, set[str]]:
    spec = SPEC.read_text(encoding="utf-8")
    research = RESEARCH.read_text(encoding="utf-8")
    return {
        "FR": set(re.findall(r"^- \*\*FR-(\d{3})\*\*", spec, re.M)),
        "SC": set(re.findall(r"^- \*\*SC-(\d{3})\*\*", spec, re.M)),
        "RI": set(re.findall(r"\*\*RI-(\d{3}) —", spec)),
        "R": set(re.findall(r"^## R-(\d{2})\b", research, re.M)),
    }


def scan(files: list[Path], ids: dict[str, set[str]]) -> list[str]:
    problems: list[str] = []
    patterns = {
        "FR": re.compile(r"\bFR-(\d{3})\b"),
        "SC": re.compile(r"\bSC-(\d{3})\b"),
        "RI": re.compile(r"\bRI-(\d{3})\b"),
        "R": re.compile(r"(?<![A-Z-])R-(\d{2})\b"),
    }
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        for kind, pattern in patterns.items():
            for number in pattern.findall(text):
                if number not in ids[kind]:
                    problems.append(f"{path.relative_to(ROOT)}: undefined {kind}-{number}")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--include-fixtures", action="store_true")
    args = parser.parse_args(argv)

    ids = defined_ids()
    files = sorted(
        p for base in (ROOT / "specs", ROOT / "docs") for p in base.rglob("*.md")
    )
    if args.include_fixtures:
        files += sorted(FIXTURES.rglob("*.md"))

    problems = scan(files, ids)
    try:
        json.loads(SCHEMA.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        problems.append(f"{SCHEMA.relative_to(ROOT)}: invalid JSON ({exc})")

    for line in problems:
        print(line)
    if problems:
        print(f"validate_docs: {len(problems)} problem(s)")
        return 1
    print(f"validate_docs: OK ({len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
