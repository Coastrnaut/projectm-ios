#!/usr/bin/env python3
"""FILE-013-R6: the app's permission catalog matches project.yml and the privacy policy.

Checks (specs/078-file-013-privacy-permission-audit, plan D10):
  * every `NS...UsageDescription` key in the projectM-iOS target of project.yml has a catalog entry
    with the identical text, and every catalog entry has its key there;
  * the full-library key `NSPhotoLibraryUsageDescription` appears nowhere in project.yml (the Photos
    picker needs none, and the app never reads the library); the add-only key
    `NSPhotoLibraryAddUsageDescription` (REC-011, ADR-0059) is allowed only in the app target;
  * the privacy policy's "Permissions and why" section lists exactly the catalog's permissions.

Usage: python3 scripts/check_permission_catalog.py [--root DIR] [--json]
Exit 0 when OK, 1 with findings. Standard library only; runs on any OS.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

APP_TARGET = "projectM-iOS"
CATALOG = Path("Apps/projectM-iOS/Coordinators/PermissionCatalog.swift")
PROJECT = Path("project.yml")
POLICY = Path("docs/privacy-policy.md")
POLICY_SECTION = "## Permissions and why"
PHOTOS_KEYS = ("NSPhotoLibraryUsageDescription",)   # full library access: never
PHOTOS_ADD_KEY = "NSPhotoLibraryAddUsageDescription"   # REC-011 (ADR-0059): the app target only

_KEY_LINE = re.compile(r'^\s+(NS\w+UsageDescription):\s*"((?:[^"\\]|\\.)*)"\s*$')
_ENTRY = re.compile(r'name:\s*"((?:[^"\\]|\\.)*)",\s*infoPlistKey:\s*"(\w+)",\s*'
                    r'usageDescription:\s*"((?:[^"\\]|\\.)*)"', re.S)
_POLICY_BULLET = re.compile(r"^- \*\*(.+?)\*\*:", re.M)


def target_block(yml: str, target: str) -> str:
    """The lines of `targets: <target>:` (two-space indent) up to the next target."""
    lines = yml.splitlines()
    out: list[str] = []
    inside = False
    for line in lines:
        if re.match(r"^  [^\s#]", line):        # a target name (or another two-space key)
            inside = line.strip() == f"{target}:"
            continue
        if re.match(r"^\S", line):               # a top-level key ends the targets section
            inside = False
            continue
        if inside:
            out.append(line)
    return "\n".join(out)


def plist_keys(yml: str, target: str = APP_TARGET) -> dict[str, str]:
    keys: dict[str, str] = {}
    for line in target_block(yml, target).splitlines():
        m = _KEY_LINE.match(line)
        if m:
            keys[m.group(1)] = m.group(2)
    return keys


def catalog_entries(swift: str) -> list[tuple[str, str, str]]:
    """(name, key, usage text) per catalog entry, in order."""
    return [(m.group(1), m.group(2), m.group(3)) for m in _ENTRY.finditer(swift)]


def policy_names(policy: str) -> list[str]:
    start = policy.find(POLICY_SECTION)
    if start < 0:
        return []
    rest = policy[start + len(POLICY_SECTION):]
    end = rest.find("\n## ")
    section = rest if end < 0 else rest[:end]
    return _POLICY_BULLET.findall(section)


def problems(yml: str, swift: str, policy: str) -> list[str]:
    found: list[str] = []
    keys = plist_keys(yml)
    entries = catalog_entries(swift)
    if not entries:
        found.append("catalog: no entries found")
    catalog = {key: text for _, key, text in entries}
    for key in sorted(set(keys) - set(catalog)):
        found.append(f"{key}: in project.yml ({APP_TARGET}) but not in the catalog")
    for key in sorted(set(catalog) - set(keys)):
        found.append(f"{key}: in the catalog but not in project.yml ({APP_TARGET})")
    for key in sorted(set(keys) & set(catalog)):
        if keys[key] != catalog[key]:
            found.append(f"{key}: the catalog's text differs from project.yml")
    for key in PHOTOS_KEYS:
        if key in yml:
            found.append(f"{key}: Photos library keys are not allowed (the picker needs no permission)")
    if yml.count(PHOTOS_ADD_KEY) > target_block(yml, APP_TARGET).count(PHOTOS_ADD_KEY):
        found.append(f"{PHOTOS_ADD_KEY}: allowed only in the {APP_TARGET} target (REC-011, ADR-0059)")
    names = [name for name, _, _ in entries]
    listed = policy_names(policy)
    if not listed:
        found.append(f"privacy policy: no '{POLICY_SECTION}' bullets found")
    for name in names:
        if name not in listed:
            found.append(f"privacy policy: '{name}' is in the catalog but not in '{POLICY_SECTION}'")
    for name in listed:
        if name not in names:
            found.append(f"privacy policy: '{name}' is listed but is not a catalog permission")
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    root: Path = args.root
    yml = (root / PROJECT).read_text(encoding="utf-8")
    swift = (root / CATALOG).read_text(encoding="utf-8")
    policy = (root / POLICY).read_text(encoding="utf-8")
    found = problems(yml, swift, policy)
    permissions = [name for name, _, _ in catalog_entries(swift)]
    if args.json:
        print(json.dumps({"ok": not found, "permissions": permissions, "problems": found}, indent=2))
    elif found:
        for problem in found:
            print(f"FAIL {problem}")
    else:
        print(f"OK: {len(permissions)} permissions ({', '.join(permissions)}); no full Photos library key")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
