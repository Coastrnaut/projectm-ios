#!/usr/bin/env python3
"""Constitution compliance check, run on every merge (tasks T014/T015).

Enforces, for source under Apps/ and Packages/ (Vendor/ is upstream and excluded):
  * Constitution I / FR-003: no private framework paths and no dynamic symbol or class lookup
    by string (dlsym, dlopen, NSClassFromString, NSSelectorFromString, performSelector).
  * FR-009 / ADR-0001: no ReplayKit.
  * Constitution VI / ADR-0001: ScreenCaptureKit imported only inside
    Packages/CaptureKit/Sources/CaptureKit/ScreenCapture/.
  * FR-068: no networking APIs (URLSession, Network framework, CFNetwork, sockets, WebKit).
  * Research R-16: no entitlements or background modes in project.yml.

Exit 0 when clean, 1 with a list of violations otherwise.
Use --paths to scan specific files or directories (tests use this with scripts/fixtures/).
Standard library only; runs on Windows and macOS.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRS = [ROOT / "Apps", ROOT / "Packages"]
SOURCE_SUFFIXES = {".swift", ".m", ".mm", ".h", ".hpp", ".c", ".cpp"}
SCK_ALLOWED = ROOT / "Packages" / "CaptureKit" / "Sources" / "CaptureKit" / "ScreenCapture"

RULES: list[tuple[str, re.Pattern[str]]] = [
    ("ReplayKit is excluded (FR-009)", re.compile(r"\bimport\s+ReplayKit\b|<ReplayKit/")),
    ("private framework path (Constitution I)", re.compile(r"PrivateFrameworks")),
    ("dynamic symbol lookup (Constitution I)", re.compile(r"\b(dlsym|dlopen)\s*\(")),
    ("class/selector lookup by string (Constitution I)",
     re.compile(r"\b(NSClassFromString|NSSelectorFromString|performSelector)\b")),
    ("networking API (FR-068)",
     re.compile(r"\bURLSession\b|\bimport\s+Network\b|\bNWConnection\b|\bCFNetwork\b|"
                r"\bimport\s+WebKit\b|\bWKWebView\b|\bCFSocket\b|<sys/socket\.h>")),
]
SCK_IMPORT = re.compile(r"\bimport\s+ScreenCaptureKit\b|<ScreenCaptureKit/")
ENTITLEMENT_KEYS = re.compile(r"^\s*(entitlements|UIBackgroundModes|com\.apple\.security\.application-groups)\s*:",
                              re.M)


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def source_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for base in paths:
        if base.is_file():
            files.append(base)
        elif base.is_dir():
            files += [p for p in base.rglob("*") if p.suffix in SOURCE_SUFFIXES]
    return sorted(files)


def check_file(path: Path) -> list[str]:
    text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
    found = [f"{path}: {name}" for name, rx in RULES if rx.search(text)]
    if SCK_IMPORT.search(text):
        try:
            path.resolve().relative_to(SCK_ALLOWED.resolve())
        except ValueError:
            found.append(f"{path}: ScreenCaptureKit imported outside CaptureKit/ScreenCapture/ (Constitution VI)")
    return found


def check_project_yml(path: Path) -> list[str]:
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8")
    return [f"{path}: '{m.group(1)}' not allowed by research R-16" for m in ENTITLEMENT_KEYS.finditer(text)]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Constitution compliance check")
    parser.add_argument("--paths", nargs="*", type=Path, help="scan these instead of Apps/ and Packages/")
    args = parser.parse_args(argv)

    targets = args.paths if args.paths else SOURCE_DIRS
    violations = [v for f in source_files(targets) for v in check_file(f)]
    if not args.paths:
        violations += check_project_yml(ROOT / "project.yml")

    for v in violations:
        print(v)
    if violations:
        print(f"check_compliance: {len(violations)} violation(s)")
        return 1
    print("check_compliance: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
