# Implementation Plan: FILE-005 Local Library Backup

**Branch**: `feature/file-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/114-file-005-local-library-backup/spec.md`

## Summary

A new Linux-testable package, `Packages/LibraryBackup`, reads the user's library (the folders in
Application Support plus a dictionary of settings handed over by the app) into one logical value,
writes it as a checksummed archive (`.pmbackup`, FILE-002's `PortableArchive`), reads it back with
limits, compares libraries record by record (the "exact logical records" function), plans a restore
with FILE-004's choices and installs it all or nothing: every folder that changes is built in a
staging area, swapped in under a journal, and settings are handed back to the app after the commit
point. Show merges reuse FILE-004's scene installer on the staged copy of the show folder.

The app adds a small `LibraryBackupCoordinator` (back up, pick, preview, request, cancel, result), a
`LibraryBackupSection` in Settings › Storage, a launch hook in `AppCoordinator.init` that finishes a
pending restore before any store loads, a UserDefaults bridge for the setting values, DEBUG launch
arguments for the UI test, and a privacy-policy sentence.

In `Packages/LibraryBackup` (new; Foundation + LocalPortability, PresetLibrary, ShowControl,
SceneFormat):

- `LibraryBackupFormat`: format name `org.projectmios.library-backup`, version 1, limits, schema,
  manifest, migration table, error words.
- `LibraryFolders`: the five folders (Show, Scenes, UserPresets, PresetCollections, Photos) and the
  restore work folder under one root.
- `LibrarySettingValue`, `LibrarySettingsPolicy`: typed values; the included keys.
- `LibraryContents` + `LibraryContentsReader`: the logical library, with exclusions counted.
- `LibraryBackupWriter` / `LibraryBackupReader`: contents ↔ archive bytes.
- `LibraryRecords`: the logical-equality function (FILE-005-R9).
- `LibraryRestorePlanner`: the dry run (pure over two `LibraryContents`).
- `LibraryRestoreInstaller`: staging, journal, swap, recovery, fault hook.
- `LibraryRestoreRequest`: the pending request (backup copy + choice) and its launch-time runner.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), Swift 6 language mode; CI also Xcode 26.

**Primary Dependencies**: Foundation, SwiftUI, UniformTypeIdentifiers; local packages
LocalPortability, PresetLibrary, ShowControl (ShowStorage), SceneFormat.

**Storage**: `Application Support/{Show,Scenes,UserPresets,PresetCollections,Photos}` (read, and
swapped on restore); `Application Support/LibraryRestore` (pending request, staging, journal, last
result); `tmp/LibraryBackup` (the file offered to the exporter).

**Testing**: XCTest: LibraryBackup package tests (host and Linux), an ImportFuzz suite for the backup
reader, app unit tests, one XCUITest on an own iOS 27.2 simulator.

**Target Platform**: iOS/iPadOS 26.0+. **Project Type**: Mobile app with SwiftPM packages.

**Performance Goals**: Back up and restore of a typical library (tens of scenes, hundreds of presets)
in well under a second on the host; unit tests use a few records (owner rule 7).

**Constraints**: Public APIs only, no networking, typed closures, no long untyped numeric
expressions, small SwiftUI bodies, no wall-clock assertions, no main-actor mutation in
setUp/tearDown, no C stdio globals.

**Scale/Scope**: 256 cues, 1,000 presets, 100 collections, 64 photos; 512 MiB file cap.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: Foundation file APIs, SwiftUI `fileExporter`/`fileImporter` |
| VI Modular boundaries | Pass: format, planner and installer in a package (Linux-testable); UI and UserDefaults in the app |
| IX Pinned dependencies | Pass: only existing local packages |
| X Evidence-based quality | Pass: round-trip acceptance test, fault injection at every file operation, recovery tests, fuzz suite, simulator UI test |
| Security | Pass: backups are untrusted: bounded archive reader, checksums, safe paths, every record re-read by its own decoder, presets re-checked, nothing executed |
| Privacy | Pass: no networking; the backup leaves the device only where the user saves it; no entitlement, no device switches; privacy policy updated |

Re-checked after Phase 1 design: unchanged.

## Project Structure

```text
specs/114-file-005-local-library-backup/  plan.md research.md data-model.md quickstart.md contracts/library-backup.md tasks.md
docs/adr/0040-local-library-backup.md            (format and exclusions)
Packages/LibraryBackup/                          (new package; Sources/LibraryBackup, Tests/LibraryBackupTests)
Packages/ImportFuzz/Package.swift                (LibraryBackup dependency)
Packages/ImportFuzz/Tests/ImportFuzzTests/LibraryBackupFuzzTests.swift   (new)
.github/workflows/ios-ci.yml                     (LibraryBackup in the package lists)
project.yml                                      (package and app dependency)
Apps/projectM-iOS/Coordinators/LibraryBackupCoordinator.swift   (new)
Apps/projectM-iOS/Coordinators/LibrarySettingsBridge.swift      (new: UserDefaults ↔ values)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift             (launch hook, property)
Apps/projectM-iOS/Views/LibraryBackupSection.swift              (new)
Apps/projectM-iOS/Views/StorageUsageView.swift                  (the section)
Apps/projectM-iOS/Views/SettingsView.swift, VisualizerView.swift (pass the coordinator)
Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift             (new)
Apps/projectM-iOS/UITests/LibraryBackupUITests.swift            (new)
docs/privacy-policy.md
```

**Structure Decision**: A separate package because the backup depends on both PresetLibrary and
ShowControl, which do not depend on each other, and the logic must run on Linux.

## Complexity Tracking

| Item | Why needed | Simpler alternative rejected because |
|---|---|---|
| Restore at next launch | The running app holds the library in memory and writes it back | Reloading every coordinator in place touches most of the app and races with autosave |
| Directory swap under a journal | Several folders must change together | Per-store transactions cannot be committed together |
