# Implementation Plan: PRE-017 Preset Restore Points

**Branch**: `feature/pre-017` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Every saved text change of a user preset keeps the replaced text as a version: the text is copied
content-addressed into `UserPresets/versions/<sha256>.milk` and listed in a sidecar `UserPresets/history.json`
(schema 1). `UserPresetStore.replaceContents` becomes one transaction over text, version, list and record;
pruning drops the oldest versions past 10 per preset, 500 in total or 50 MB, and deletes a version text only
when no remaining version names it. `UserPresetLibrary` adds `versions(of:)`, `versionText(of:sha256:)` and
`revert(_:to:expectedSHA256:)`; revert re-enters the PRE-015 edit path with the version's exact bytes. The app
adds "Versions…" on editable rows: a sheet listing versions with Preview (read-only text) and Revert.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2; CI Xcode 26)
**Primary Dependencies**: Foundation, LocalPortability (`DocumentSchema` limits for the list file), SwiftUI in the app
**Storage**: `Application Support/UserPresets/history.json` (schema 1, atomic) and `UserPresets/versions/`
**Testing**: XCTest (PresetLibrary and LibraryBackup on the host; app UI test on the private simulator "PRE17 iPhone 17", iOS 27.2)
**Target Platform**: iOS 26+; packages build on Linux
**Performance Goals**: an edit adds one file copy and one small JSON write; listing reads the in-memory list
**Constraints**: no new UserDefaults keys; no networking; every file operation through the store's path guard
**Scale/Scope**: ≤10 versions per preset, ≤500 total, ≤50 MB of version texts

## Constitution Check

- I Public APIs only, no networking: Foundation and SwiftUI. PASS
- VI Modular boundaries: model, list file and store logic in `PresetLibrary` (Foundation only, Linux). PASS
- Privacy: versions stay on the device; not in backups, exports, diagnostics or UserDefaults. PASS
- X Evidence-based quality: package tests prove the acceptance (sha match, file-set diff); UI test on a simulator; no device claim. PASS

Post-design re-check: unchanged, PASS.

## Project Structure

```text
Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/
  UserPresetHistory.swift         # UserPresetVersion, UserPresetVersionLimits, UserPresetHistoryFile, pruning
  UserPresetStore+History.swift   # list load/save, version files, GC
  UserPresetStore.swift           # replaceContents and remove become history-aware; load hooks
  UserPresetLibrary.swift         # edit path shared with revert; versions(of:), versionText, revert
Packages/PresetLibrary/Tests/PresetLibraryTests/UserPresetHistoryTests.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibraryFolders.swift (doc comment only)
Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupPresetVersionTests.swift
Apps/projectM-iOS/Coordinators/UserPresetsCoordinator+Versions.swift
Apps/projectM-iOS/Views/UserPresetVersionsView.swift (+ "Versions…" row hooks in PresetBrowserView)
Apps/projectM-iOS/Debug/UITestPresetVersionsFixture.swift (+ one seed call in AppCoordinator's UI-test reset)
Apps/projectM-iOS/UITests/UserPresetVersionsUITests.swift
```

**Structure Decision**: extend the PRE-012 store (one owner of the folder and its path guard) with a sidecar
list, rather than a second store, so the edit stays a single transaction.

## Complexity Tracking

None.
