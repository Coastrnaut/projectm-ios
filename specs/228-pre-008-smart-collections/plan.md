# Implementation Plan: PRE-008 Smart Collections

**Branch**: `feature/pre-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Smart collections are named rule sets (match All/Any over tag, not-tag, pack, motion, colour and Favorites
conditions) kept in their own versioned file beside the manual collections. Membership is computed by a pure
Foundation matcher in `PresetLibrary` from the library, the PRE-003 tag index, favorites and the PRE-004/PRE-005
filters: a de-duplicated (preset ID and content hash), alphabetical list. The app merges smart memberships into
the existing `.collection(id)` scope, lists smart collections in the Collections screen with a Smart marker, and
offers a rule editor with a live count. FILE-005 backs the file up as its own record.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2; CI Xcode 26)
**Primary Dependencies**: Foundation, LocalPortability (`DocumentSchema`), SwiftUI in the app
**Storage**: `Application Support/PresetCollections/smart-collections.json` (schema 1, atomic writes)
**Testing**: XCTest (PresetLibrary and LibraryBackup packages on the host; app unit and UI tests on the private simulator "PRE8 iPhone 17", iOS 27.2)
**Target Platform**: iOS 26+; packages build on Linux
**Performance Goals**: membership is set operations over the PRE-003/4/5 indexes; a pack condition scans the library once (12,847 presets) per evaluation
**Constraints**: no new UserDefaults keys; no networking; Linux-buildable package code
**Scale/Scope**: at most 100 smart collections × 32 conditions × 64 values

## Constitution Check

- Public APIs only, no networking: pure Foundation and SwiftUI. PASS
- Local-first, privacy: rules stay on the device and in the user's local backup. PASS
- Testable logic in packages (Constitution VI): model, matcher, file and store in `PresetLibrary`. PASS
- Honest reporting: simulator UI evidence only; no device claims. PASS

## Project Structure

```text
Packages/PresetLibrary/Sources/PresetLibrary/Smart/
  PresetSmartCollection.swift        # model, condition kinds, limits, errors
  PresetSmartMatcher.swift           # context + membership
  PresetSmartCollectionsFile.swift   # versioned document, schema, migrations
  PresetSmartCollectionStore.swift   # transactional store
Packages/PresetLibrary/Tests/PresetLibraryTests/PresetSmartCollectionTests.swift
Packages/LibraryBackup/Sources/LibraryBackup/ (LibraryFolders, LibraryContents, LibraryBackupArchive,
  LibraryBackupFormat, LibraryRecords, LibraryRestorePlan, LibraryRestoreInstaller, LibraryEraseInventory)
Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupSmartCollectionTests.swift
Apps/projectM-iOS/Coordinators/PresetCoordinator+Smart.swift (+ small hooks in PresetCoordinator.swift, AppCoordinator.swift)
Apps/projectM-iOS/Views/SmartCollectionViews.swift (section, detail, rule editor; hook in PresetCollectionsView/PresetBrowserView)
Apps/projectM-iOS/Tests/PresetSmartCollectionAppTests.swift
Apps/projectM-iOS/UITests/PresetSmartCollectionUITests.swift
```

**Structure Decision**: follow PRE-003/PRE-016 (own file in the collections folder, own backup record) and PRE-007
(store transactions, name rules, scope).

## Complexity Tracking

None.
