# Quickstart: PRE-011 Preset Notes

1. Package tests: `swift test --package-path Packages/PresetLibrary --filter PresetNote` and `swift test --package-path Packages/LibraryBackup --filter LibraryBackupNote` — relaunch, limits, newer/unreadable files, backup round trip, restore merge, erase.
2. Compliance: `python3 scripts/check_compliance.py` (OK) and `python3 scripts/test_scripts.py` (the notes-in-diagnostics rule test).
3. App tests on "PRE11 iPhone 17": `-only-testing:projectM-iOSTests/PresetNoteAppTests` — relaunch through the app's coordinator, diagnostics contain no marker note, search finds a note, integrity reports a dangling note.
4. UI test: `-only-testing:projectM-iOSUITests/PresetNoteUITests` — add a note, see the row indicator, reopen and see the text.
