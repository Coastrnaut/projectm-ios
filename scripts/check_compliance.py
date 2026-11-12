#!/usr/bin/env python3
"""Constitution compliance check, run on every merge (tasks T014/T015).

Enforces, for source under Apps/ and Packages/ (Vendor/ is upstream and excluded):
  * Constitution I / FR-003: no private framework paths and no dynamic symbol or class lookup
    by string (dlsym, dlopen, NSClassFromString, NSSelectorFromString, performSelector).
  * FR-009 / ADR-0001: no ReplayKit, including kind-qualified Swift imports
    (`import struct ReplayKit.X`; ADR-0001 owner ruling 13).
  * Constitution VI / ADR-0001: ScreenCaptureKit imported only inside
    Packages/CaptureKit/Sources/CaptureKit/ScreenCapture/ (same import forms).
  * FR-068 (amended 2026-11-12): no networking APIs (URLSession, CFNetwork, sockets, WebKit)
    anywhere; the Network framework only inside
    Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport/ (local OSC, off by default).
  * Research R-16: no entitlements or background modes in project.yml, in any YAML key form
    (plain, quoted, or flow style; ADR-0001 owner ruling 13). YAML comments are ignored.
  * ADR-0001 Decision 6, the one entitlement exception: project.yml may set
    CODE_SIGN_ENTITLEMENTS only to Apps/CaptureLab/CaptureLab.entitlements, and every
    *.entitlements file in the repository may hold only allowlisted keys with allowlisted values.

Exit 0 when clean, 1 with a list of violations otherwise.
Use --paths to scan specific files or directories (tests use this with scripts/fixtures/).
Standard library only; runs on Windows and macOS.
"""
from __future__ import annotations

import argparse
import os
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRS = [ROOT / "Apps", ROOT / "Packages"]
SOURCE_SUFFIXES = {".swift", ".m", ".mm", ".h", ".hpp", ".c", ".cpp"}
SCK_ALLOWED = ROOT / "Packages" / "CaptureKit" / "Sources" / "CaptureKit" / "ScreenCapture"

# Swift import kinds (`import struct ReplayKit.RPScreenRecorder`). Attributes such as
# @_implementationOnly, @_exported or @preconcurrency come before `import`, so they need no
# extra handling.
IMPORT_KIND = r"(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?"


def swift_import(module: str) -> str:
    return rf"\bimport\s+{IMPORT_KIND}{module}\b"


RULES: list[tuple[str, re.Pattern[str]]] = [
    ("ReplayKit is excluded (FR-009)", re.compile(swift_import("ReplayKit") + r"|<ReplayKit/")),
    ("private framework path (Constitution I)", re.compile(r"PrivateFrameworks")),
    ("dynamic symbol lookup (Constitution I)", re.compile(r"\b(dlsym|dlopen)\s*\(")),
    ("class/selector lookup by string (Constitution I)",
     re.compile(r"\b(NSClassFromString|NSSelectorFromString|performSelector)\b")),
    ("networking API (FR-068)",
     re.compile(r"\bURLSession\b|\bCFNetwork\b|\bimport\s+WebKit\b|\bWKWebView\b|"
                r"\bCFSocket\b|<sys/socket\.h>")),
]
# FR-068 as amended 2026-11-12 (owner ruling, ADR-0008): the Network framework is allowed in
# exactly one folder, the local-network OSC transport, which is off by default. Everywhere
# else it stays forbidden, and no other networking API is allowed anywhere.
NETWORK_FRAMEWORK = re.compile(r"\bimport\s+Network\b|\bNW(Connection|Listener|Browser|"
                               r"ConnectionGroup|PathMonitor|Endpoint|Parameters)\b")
OSC_ALLOWED = (ROOT / "Packages" / "PerformanceControl" / "Sources" / "PerformanceControl"
               / "OSCTransport")
SCK_IMPORT = re.compile(swift_import("ScreenCaptureKit") + r"|<ScreenCaptureKit/")

# A YAML mapping key starts a line (optionally as a `- ` list item) or follows `{` or `,` in
# flow style, and may be single- or double-quoted. Comments are stripped before matching.
YAML_KEY_START = r"(?:^|[{,])[ \t]*(?:-[ \t]+)?"
FORBIDDEN_YML_KEYS = re.compile(
    YAML_KEY_START
    + r"""(["']?)(entitlements|UIBackgroundModes|com\.apple\.security\.application-groups)\1[ \t]*:""",
    re.M)
CODE_SIGN_KEY = re.compile(
    YAML_KEY_START + r"""(["']?)(CODE_SIGN_ENTITLEMENTS(?:\[[^\]\n]*\])*)\1[ \t]*:[ \t]*""", re.M)
# Every mention of the setting must be a key CODE_SIGN_KEY can check; any other form (an
# unrecognized key shape, or a reference in a value) is flagged, so Decision 6 cannot be bypassed.
CODE_SIGN_TOKEN = re.compile(r"CODE_SIGN_ENTITLEMENTS")
# ADR-0001 Decision 6: CaptureLab's Screen Recording entitlement file, the only one allowed.
ALLOWED_CODE_SIGN_ENTITLEMENTS = "Apps/CaptureLab/CaptureLab.entitlements"
# ADR-0001 Decision 6: the only entitlement keys, each with the only value, that any
# *.entitlements file in the repository may hold.
ENTITLEMENT_ALLOWLIST: dict[str, object] = {"com.apple.developer.screen-recording": True}
# Not scanned for *.entitlements: git metadata and build output anywhere (case-insensitive),
# upstream Vendor/ and the autonomous run's .autonomous/ at the repository root, and agent
# worktrees under .claude/worktrees/.
SKIP_DIRS = {".git", "build", ".build", "deriveddata"}
# .autonomous/ holds the autonomous run's feature worktrees (full checkouts, with their own Vendor/).
SKIP_ROOT_DIRS = {"Vendor", ".autonomous"}


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
    if NETWORK_FRAMEWORK.search(text):
        try:
            path.resolve().relative_to(OSC_ALLOWED.resolve())
        except ValueError:
            found.append(f"{path}: networking API (FR-068): Network framework used outside "
                         "PerformanceControl/OSCTransport/")
    if SCK_IMPORT.search(text):
        try:
            path.resolve().relative_to(SCK_ALLOWED.resolve())
        except ValueError:
            found.append(f"{path}: ScreenCaptureKit imported outside CaptureKit/ScreenCapture/ (Constitution VI)")
    return found


def strip_yaml_comments(text: str) -> str:
    """Drop YAML comments: a `#` at line start or after whitespace, outside quoted scalars."""
    lines = []
    for line in text.splitlines():
        quote = None
        for i, ch in enumerate(line):
            if quote:
                if ch == quote:
                    quote = None
            elif ch in "\"'" and (i == 0 or line[i - 1] in " \t{[,:-?"):
                quote = ch
            elif ch == "#" and (i == 0 or line[i - 1] in " \t"):
                line = line[:i]
                break
        lines.append(line)
    return "\n".join(lines)


def yaml_scalar(rest: str) -> str:
    """The scalar at the start of `rest` (the text after `key:` on the same line), unquoted."""
    if rest[:1] in ("'", '"'):
        end = rest.find(rest[0], 1)
        return rest[1:end] if end > 0 else rest[1:]
    return re.split(r"[,}\]]", rest, maxsplit=1)[0].strip()


# ADR-0001 ruling 17 (2026-11-09): the one background-mode exception, written exactly in flow style.
ALLOWED_BACKGROUND_MODES = re.compile(r"""[ \t]*\[[ \t]*(["']?)screen-capture\1[ \t]*\][ \t]*""")


def allowed_background_modes(m: re.Match[str], text: str) -> bool:
    """True only for `UIBackgroundModes: [screen-capture]` (quoted or not), nothing else."""
    if m.group(2) != "UIBackgroundModes":
        return False
    rest = text[m.end():].split("\n", 1)[0]
    return ALLOWED_BACKGROUND_MODES.fullmatch(rest) is not None


def check_project_yml(path: Path) -> list[str]:
    if not path.exists():
        return []
    text = strip_yaml_comments(path.read_text(encoding="utf-8"))
    found = [f"{path}: '{m.group(2)}' not allowed by research R-16"
             for m in FORBIDDEN_YML_KEYS.finditer(text)
             if not allowed_background_modes(m, text)]
    keys = list(CODE_SIGN_KEY.finditer(text))
    for m in keys:
        value = yaml_scalar(text[m.end():].split("\n", 1)[0])
        if value != ALLOWED_CODE_SIGN_ENTITLEMENTS:
            found.append(f"{path}: '{m.group(2)}' must be {ALLOWED_CODE_SIGN_ENTITLEMENTS} "
                         f"(found '{value}'; ADR-0001 Decision 6)")
    if len(CODE_SIGN_TOKEN.findall(text)) > len(keys):
        found.append(f"{path}: CODE_SIGN_ENTITLEMENTS in a form this check cannot verify "
                     f"(ADR-0001 Decision 6)")
    return found


def entitlements_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        here = Path(dirpath)
        dirnames[:] = sorted(d for d in dirnames
                             if d.lower() not in SKIP_DIRS
                             and not (here == root and d in SKIP_ROOT_DIRS)
                             and not (here.name == ".claude" and d == "worktrees"))
        files += [here / f for f in filenames if f.endswith(".entitlements")]
    return sorted(files)


def check_entitlements_file(path: Path) -> list[str]:
    try:
        with path.open("rb") as f:
            data = plistlib.load(f)
    except Exception as exc:  # any failure to parse is a violation
        return [f"{path}: not a readable property list ({type(exc).__name__}; ADR-0001 Decision 6)"]
    if not isinstance(data, dict):
        return [f"{path}: top level is not a dictionary (ADR-0001 Decision 6)"]
    found = []
    for key, value in data.items():
        if key not in ENTITLEMENT_ALLOWLIST:
            found.append(f"{path}: entitlement '{key}' not allowed (ADR-0001 Decision 6)")
            continue
        allowed = ENTITLEMENT_ALLOWLIST[key]
        if type(value) is not type(allowed) or value != allowed:
            found.append(f"{path}: entitlement '{key}' must be {allowed!r} "
                         f"(found {value!r}; ADR-0001 Decision 6)")
    return found


def check_entitlements(root: Path) -> list[str]:
    return [v for f in entitlements_files(root) for v in check_entitlements_file(f)]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Constitution compliance check")
    parser.add_argument("--paths", nargs="*", type=Path, help="scan these instead of Apps/ and Packages/")
    args = parser.parse_args(argv)

    targets = args.paths if args.paths else SOURCE_DIRS
    violations = [v for f in source_files(targets) for v in check_file(f)]
    if not args.paths:
        violations += check_project_yml(ROOT / "project.yml")
        violations += check_entitlements(ROOT)

    for v in violations:
        print(v)
    if violations:
        print(f"check_compliance: {len(violations)} violation(s)")
        return 1
    print("check_compliance: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
