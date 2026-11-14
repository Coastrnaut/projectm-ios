# Implementation Plan: FILE-011 Local Data Erase

**Branch**: `feature/file-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/120-file-011-local-data-erase/spec.md`

## Summary

The erase lives beside FILE-005's backup in `Packages/LibraryBackup` (it reuses `LibraryFolders`,
`LibrarySettingsPolicy`, `LibraryRecords` and the journaled launch-time pattern) as four new files:

- `LibraryErasePolicy`: the six categories, their folders and setting keys, the never-erased keys.
- `LibraryEraseInventory`: counts per category (stores' readers) and sizes (FILE-009's
  `StorageUsageCalculator`).
- `LibraryErasePlanner` + `LibraryEraser`: the plan (folders, keys, media references to release) and
  its all-or-nothing execution: folders moved to `LibraryErase/trash/` under a journal, commit point,
  then settings, media releases (FILE-008 `ContentAddressedMediaFolder.release`) and deletion;
  `recover` rolls a prepared journal back and a committed one forward; a fault hook on every file
  operation.
- `LibraryEraseRequest`: the pending request, the launch-time runner and the result note.

The app adds `LibraryEraseCoordinator` (owned by `LibraryBackupCoordinator`, so `AppCoordinator`,
`SettingsView` and `StorageUsageView` change by a line or two), `LibraryEraseSection` and
`LibraryEraseSheet` (checkboxes, counts, Back Up First, confirmation), the launch hook (erase before
the FILE-005 restore, both before any store loads), a DEBUG probe and a UI test.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), Swift 6 language mode; CI also Xcode 26.

**Primary Dependencies**: Foundation, SwiftUI; local packages LibraryBackup (LocalPortability,
PresetLibrary, ShowControl/ShowStorage, SceneFormat).

**Storage**: `Application Support/{Show,Scenes,UserPresets,PresetCollections,Photos,Videos,AudioLibrary}`
(moved and deleted); `Application Support/LibraryErase/` (request.json, erase.journal.json, trash/,
last-result.json); UserDefaults keys of FILE-011-R4.

**Testing**: XCTest: LibraryBackup package tests (host; Linux in CI), app unit tests, one XCUITest on
an own iOS 27.2 simulator.

**Target Platform**: iOS/iPadOS 26.0+. **Project Type**: Mobile app with SwiftPM packages.

**Performance Goals**: An erase is a few renames plus deletion; inventory off the main thread; unit
tests use small fixtures (owner rule 7: about 1-2 s each, UI test under 30 s).

**Constraints**: Public APIs only, no networking, typed closures, no long untyped numeric expressions,
small SwiftUI bodies (`-warn-long-function-bodies=300`), no wall-clock assertions, no main-actor
mutation in setUp/tearDown, no C stdio globals.

**Scale/Scope**: Six categories, seven folders, about 35 setting keys.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: FileManager renames and removal, UserDefaults, SwiftUI |
| VI Modular boundaries | Pass: policy, planner, eraser and launch runner in the Linux-testable package; UI and UserDefaults in the app |
| IX Pinned dependencies | Pass: no new dependency |
| X Evidence-based quality | Pass: per-category acceptance with records and tree snapshots, fault injection at every file operation, recovery tests, reference tests, a no-write-back test, a simulator UI test |
| Security / Privacy | Pass: deletes only the app's own folders under its library root; never the bundle, the purchase, caches or system state; no networking; privacy policy updated |

Re-checked after Phase 1 design: unchanged.

## Project Structure

```text
specs/120-file-011-local-data-erase/  plan.md research.md data-model.md quickstart.md contracts/library-erase.md tasks.md
docs/adr/0048-local-data-erase.md
Packages/LibraryBackup/Sources/LibraryBackup/LibraryErasePolicy.swift      (new)
Packages/LibraryBackup/Sources/LibraryBackup/LibraryEraseInventory.swift   (new)
Packages/LibraryBackup/Sources/LibraryBackup/LibraryEraser.swift           (new: plan, run, recover)
Packages/LibraryBackup/Sources/LibraryBackup/LibraryEraseRequest.swift     (new: request, launch, result)
Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryErase*Tests.swift   (new)
Apps/projectM-iOS/Coordinators/LibraryEraseCoordinator.swift              (new)
Apps/projectM-iOS/Coordinators/LibraryBackupCoordinator.swift             (owns it; launch hook; mutual exclusion)
Apps/projectM-iOS/Coordinators/LibrarySettingsBridge.swift                (remove keys; read named keys)
Apps/projectM-iOS/Views/LibraryEraseSection.swift                         (new: section, sheet, confirmation)
Apps/projectM-iOS/Views/StorageUsageView.swift                            (two lines: the section, last; the sheet)
Apps/projectM-iOS/Views/LibraryBackupSection.swift                        (Restore disabled while an erase waits)
Apps/projectM-iOS/Debug/UITestLibraryBackup.swift                         (sheet body split for the type checker)
scripts/check_status_events.py                                            (the erase files are checked)
Apps/projectM-iOS/Tests/LibraryEraseAppTests.swift                        (new)
Apps/projectM-iOS/UITests/LibraryEraseUITests.swift                       (new)
docs/privacy-policy.md
```

**Structure Decision**: Inside `LibraryBackup`, because the erase is the inverse of the backup over the
same inventory and must run in the same launch hook; a separate package would duplicate the folder
and key lists.

## Complexity Tracking

| Item | Why needed | Simpler alternative rejected because |
|---|---|---|
| Erase at next launch | The running app's stores, autosave and settings would write erased data back | Resetting every coordinator in place touches most of the app and races with autosave and scene history |
| Move-aside under a journal | Several folders and keys must go together, all or nothing | Deleting folder by folder leaves a half-erased library on a failure |
