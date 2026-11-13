#!/usr/bin/env python3
"""Check a built app against its privacy manifest (task T106; FR-066). macOS only (uses nm).

Scans the app executable and every embedded framework for the symbols of Apple's required-reason
API categories, then checks that the bundled PrivacyInfo.xcprivacy declares each category found,
with at least one reason, that every declared reason is one this app is allowed to give for its
category (ALLOWED_REASONS; REC-015 adds Disk space, E174.1), and that it declares no tracking and no
collected data. Xcode's privacy report only
adds up manifests; this scan is what finds an undeclared API.

    python3 scripts/check_privacy_manifest.py <path to projectM-iOS.app>
"""
from __future__ import annotations

import plistlib
import subprocess
import sys
from pathlib import Path

# Imported (undefined) symbols per category, from Apple's "Describing use of required reason API".
CATEGORIES = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": {
        "_stat", "_fstat", "_lstat", "_fstatat", "_stat64", "_fstat64", "_lstat64", "_getattrlist",
        "_getattrlistbulk", "_fgetattrlist", "_getattrlistat", "_NSFileCreationDate",
        "_NSFileModificationDate", "_NSURLContentModificationDateKey", "_NSURLCreationDateKey"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"_mach_absolute_time"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {
        "_statfs", "_statvfs", "_fstatfs", "_fstatvfs", "_NSFileSystemFreeSize", "_NSFileSystemSize",
        "_NSURLVolumeAvailableCapacityKey", "_NSURLVolumeAvailableCapacityForImportantUsageKey",
        "_NSURLVolumeAvailableCapacityForOpportunisticUsageKey", "_NSURLVolumeTotalCapacityKey"},
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {"_OBJC_CLASS_$_UITextInputMode"},
    "NSPrivacyAccessedAPICategoryUserDefaults": {"_OBJC_CLASS_$_NSUserDefaults"},
}
# The reasons this app may declare, per category (Apple's codes for the uses the app actually has):
# UserDefaults CA92.1 (the app's own settings), SystemBootTime 35F9.1 (elapsed time in the app),
# FileTimestamp C617.1 (files inside the app bundle), DiskSpace E174.1 (REC-015: check there is
# enough space to write a recording; the value never leaves the device). Any other reason is flagged.
ALLOWED_REASONS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1"},
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"C617.1"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {"E174.1"},
}
# Swift's ProcessInfo.systemUptime goes through -[NSProcessInfo systemUptime]; look for the selector.
SELECTORS = {"NSPrivacyAccessedAPICategorySystemBootTime": [b"systemUptime"],
             "NSPrivacyAccessedAPICategoryActiveKeyboards": [b"activeInputModes"]}


def binaries(app: Path) -> list[Path]:
    info = plistlib.loads((app / "Info.plist").read_bytes())
    executable = info.get("CFBundleExecutable", app.stem)
    found = [app / executable]
    # Debug builds (ENABLE_DEBUG_DYLIB) keep the app's code in `<executable>.debug.dylib`; the
    # executable is only a stub, so scan the dylib too or a Debug scan finds nothing (REC-015).
    found.append(app / f"{executable}.debug.dylib")
    for framework in sorted((app / "Frameworks").glob("*.framework")):
        found.append(framework / framework.stem)
    return [path for path in found if path.exists()]


def categories_used(binary: Path) -> dict[str, set[str]]:
    output = subprocess.run(["nm", "-u", str(binary)], capture_output=True, text=True, check=True).stdout
    imported = {line.strip() for line in output.splitlines()}
    used = {category: imported & symbols for category, symbols in CATEGORIES.items() if imported & symbols}
    data = binary.read_bytes()
    for category, selectors in SELECTORS.items():
        hits = {selector.decode() for selector in selectors if selector + b"\0" in data}
        if hits:
            used.setdefault(category, set()).update(hits)
    return used


def manifest_problems(manifest: dict, used: dict[str, set[str]]) -> list[str]:
    """Problems of a manifest given the categories each binary uses ({binary name: categories})."""
    declared = {entry.get("NSPrivacyAccessedAPIType"): entry.get("NSPrivacyAccessedAPITypeReasons", [])
                for entry in manifest.get("NSPrivacyAccessedAPITypes", [])}
    problems = []
    if manifest.get("NSPrivacyTracking") is not False:
        problems.append("NSPrivacyTracking must be false")
    if manifest.get("NSPrivacyTrackingDomains"):
        problems.append("NSPrivacyTrackingDomains must be empty")
    if manifest.get("NSPrivacyCollectedDataTypes"):
        problems.append("NSPrivacyCollectedDataTypes must be empty (App Privacy: Data Not Collected)")
    for category, reasons in sorted(declared.items(), key=lambda item: str(item[0])):
        allowed = ALLOWED_REASONS.get(category)
        if allowed is None:
            problems.append(f"{category} is declared but has no allowed reasons in ALLOWED_REASONS")
            continue
        for reason in reasons:
            if reason not in allowed:
                problems.append(f"{category} declares reason {reason}; allowed: {', '.join(sorted(allowed))}")
    for binary, categories in sorted(used.items()):
        for category in sorted(categories):
            if not declared.get(category):
                problems.append(f"{binary} uses {category} but the manifest has no reason for it")
    return problems


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    app = Path(argv[1])
    manifest_path = app / "PrivacyInfo.xcprivacy"
    if not manifest_path.exists():
        print(f"no PrivacyInfo.xcprivacy in {app}")
        return 1
    manifest = plistlib.loads(manifest_path.read_bytes())
    declared = {entry["NSPrivacyAccessedAPIType"]: entry.get("NSPrivacyAccessedAPITypeReasons", [])
                for entry in manifest.get("NSPrivacyAccessedAPITypes", [])}
    used: dict[str, set[str]] = {}
    used_anywhere: set[str] = set()
    for binary in binaries(app):
        for category, symbols in sorted(categories_used(binary).items()):
            used_anywhere.add(category)
            used.setdefault(binary.name, set()).add(category)
            status = "declared" if declared.get(category) else "UNDECLARED"
            print(f"{binary.name}: {category} ({', '.join(sorted(symbols))}) {status}")
    problems = manifest_problems(manifest, used)
    for category in sorted(set(declared) - used_anywhere):
        print(f"note: {category} is declared but no binary uses it")
    for problem in problems:
        print(f"error: {problem}")
    print("check_privacy_manifest: " + ("OK" if not problems else f"{len(problems)} problem(s)"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
