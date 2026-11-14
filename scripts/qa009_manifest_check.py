#!/usr/bin/env python3
"""QA-009-R8 (contract M4): every identifier in the primary-screen manifest still appears in the app's source.

The manifest (`Apps/projectM-iOS/UITests/PrimaryScreensManifest.swift`) lists required controls one per line as
`RequiredControl("<identifier>", ...)`. An identifier is found when the app's Swift sources outside the test
targets contain it as a string literal (`"<identifier>"`), or contain a literal prefix of it followed by an
interpolation or a concatenation (`"license:\\(`, `"recordingQuality." +`), as dynamic identifiers are written.
Exit status 1 names each missing identifier, so a renamed control fails before any simulator run.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = Path("Apps/projectM-iOS/UITests/PrimaryScreensManifest.swift")
APP = Path("Apps/projectM-iOS")
TEST_DIRS = {"UITests", "Tests"}

CONTROL = re.compile(r'^\s*RequiredControl\("([^"]+)"', re.MULTILINE)


def manifest_identifiers(text: str) -> list[str]:
    """The required-control identifiers in manifest order (duplicates kept once)."""
    seen: list[str] = []
    for identifier in CONTROL.findall(text):
        if identifier not in seen:
            seen.append(identifier)
    return seen


def app_sources(root: Path) -> str:
    """All Swift source of the app outside its test targets, concatenated."""
    parts: list[str] = []
    for path in sorted((root / APP).rglob("*.swift")):
        if TEST_DIRS.intersection(path.relative_to(root / APP).parts):
            continue
        parts.append(path.read_text(encoding="utf-8"))
    return "\n".join(parts)


def is_present(identifier: str, source: str) -> bool:
    if f'"{identifier}"' in source:
        return True
    # A dynamic identifier: a literal prefix (ending at a separator, or before a trailing number such as
    # `showCue1`), then an interpolation or a concatenation.
    prefixes = [identifier[: index + 1] for index, char in enumerate(identifier[:-1]) if char in ".:"]
    number = re.fullmatch(r"(.*\D)\d+", identifier)
    if number:
        prefixes.append(number.group(1))
    for prefix in prefixes:
        if re.search(re.escape(f'"{prefix}') + r'(\\\(|"\s*\+)', source):
            return True
    return False


def missing(root: Path) -> list[str]:
    text = (root / MANIFEST).read_text(encoding="utf-8")
    identifiers = manifest_identifiers(text)
    if not identifiers:
        return ["<the manifest lists no RequiredControl>"]
    source = app_sources(root)
    return [identifier for identifier in identifiers if not is_present(identifier, source)]


def main(argv: list[str]) -> int:
    root = Path(argv[1]).resolve() if len(argv) > 1 else ROOT
    absent = missing(root)
    if absent:
        for identifier in absent:
            print(f"QA-009: manifest identifier not found in the app source: {identifier}")
        return 1
    count = len(manifest_identifiers((root / MANIFEST).read_text(encoding="utf-8")))
    print(f"QA-009: all {count} manifest identifiers appear in the app source")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
