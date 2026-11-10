#!/usr/bin/env python3
"""Check a built app against its privacy manifest (task T106; FR-066). macOS only (uses nm).

Scans the app executable and every embedded framework for the symbols of Apple's required-reason
API categories, then checks that the bundled PrivacyInfo.xcprivacy declares each category found,
with at least one reason, and declares no tracking and no collected data. Xcode's privacy report only
adds up manifests; this scan is what finds an undeclared API.

    python3 scripts/check_privacy_manifest.py <path to ProjectMiOS.app>
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
# Swift's ProcessInfo.systemUptime goes through -[NSProcessInfo systemUptime]; look for the selector.
SELECTORS = {"NSPrivacyAccessedAPICategorySystemBootTime": [b"systemUptime"],
             "NSPrivacyAccessedAPICategoryActiveKeyboards": [b"activeInputModes"]}


def binaries(app: Path) -> list[Path]:
    info = plistlib.loads((app / "Info.plist").read_bytes())
    found = [app / info.get("CFBundleExecutable", app.stem)]
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
    problems = []
    if manifest.get("NSPrivacyTracking") is not False:
        problems.append("NSPrivacyTracking must be false")
    if manifest.get("NSPrivacyTrackingDomains"):
        problems.append("NSPrivacyTrackingDomains must be empty")
    if manifest.get("NSPrivacyCollectedDataTypes"):
        problems.append("NSPrivacyCollectedDataTypes must be empty (App Privacy: Data Not Collected)")
    used_anywhere: set[str] = set()
    for binary in binaries(app):
        for category, symbols in sorted(categories_used(binary).items()):
            used_anywhere.add(category)
            status = "declared" if declared.get(category) else "UNDECLARED"
            print(f"{binary.name}: {category} ({', '.join(sorted(symbols))}) {status}")
            if not declared.get(category):
                problems.append(f"{binary.name} uses {category} but the manifest has no reason for it")
    for category in sorted(set(declared) - used_anywhere):
        print(f"note: {category} is declared but no binary uses it")
    for problem in problems:
        print(f"error: {problem}")
    print("check_privacy_manifest: " + ("OK" if not problems else f"{len(problems)} problem(s)"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
