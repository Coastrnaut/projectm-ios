# Implementation Plan: PRE-011 Preset Notes

**Branch**: `feature/pre-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Private free-text notes keyed by the stable preset ID, kept in their own versioned file
`PresetCollections/notes.json` beside tags, overrides and smart collections. A Foundation-only map, file and
transactional store in `PresetLibrary` (the PRE-016 lenient map plus PRE-008's migration table); the app adds a
"Note…" sheet on the browser row, a note symbol and ", has note" on rows, note matches in search, and a PRE-018
"Notes" reference store. FILE-005 backs the file up as `collections/notes.json` and merges it per preset on
restore; FILE-011 erases and counts it. A compliance rule keeps every diagnostics source from naming the notes
store, and an app test exports the diagnostics with marker notes present and finds no marker.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2; CI Xcode 26)
**Primary Dependencies**: Foundation, LocalPortability (`DocumentSchema`), SwiftUI in the app
**Storage**: `Application Support/PresetCollections/notes.json` (schema 1, atomic writes)
**Testing**: XCTest (PresetLibrary and LibraryBackup packages on the host; app unit and UI tests on the private simulator "PRE11 iPhone 17", iOS 27.2); Python unittest for the compliance rule
**Target Platform**: iOS 26+; packages build on Linux
**Performance Goals**: note lookups are dictionary reads; search adds one pass over at most 20,000 notes per query
**Constraints**: no new UserDefaults keys; no networking; nothing note-derived in any diagnostics output
**Scale/Scope**: at most 20,000 notes × 2,000 characters; file at most 8 MiB

## Constitution Check

- Public APIs only, no networking: Foundation and SwiftUI. PASS
- Privacy (Platform, Security & Privacy Constraints; FR-068): notes stay on the device and in the user's own local backup; never in diagnostics, logs, UserDefaults or shared exports; enforced by a compliance rule and tests. PASS
- Modular boundaries (VI): model, file and store in `PresetLibrary`, Linux-buildable. PASS
- Evidence-based quality (X): package, app and UI tests on the simulator; no device claims. PASS

Post-design re-check: unchanged, PASS.

## Project Structure

```text
Packages/PresetLibrary/Sources/PresetLibrary/Notes/
  PresetNoteMap.swift        # value type, validation, limits, errors
  PresetNotesFile.swift      # versioned document, schema, migrations, lenient body
  PresetNoteStore.swift      # transactional store
Packages/PresetLibrary/Sources/PresetLibrary/Integrity/ (PresetReferenceStore.notes, snapshot.notes, scanner)
Packages/PresetLibrary/Tests/PresetLibraryTests/PresetNoteTests.swift
Packages/LibraryBackup/Sources/LibraryBackup/ (LibraryFolders, LibraryContents, LibraryBackupArchive,
  LibraryBackupFormat, LibraryRecords, LibraryRestorePlan, LibraryRestoreInstaller, LibraryEraseInventory)
Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupNoteTests.swift
Apps/projectM-iOS/Coordinators/PresetCoordinator+Notes.swift (+ init hook in PresetCoordinator, AppCoordinator,
  search in PresetCoordinator+Tags, integrity in PresetCoordinator+Integrity, prune in UserPresetsCoordinator)
Apps/projectM-iOS/Views/PresetNoteView.swift (+ row hooks in PresetBrowserView)
Apps/projectM-iOS/Tests/PresetNoteAppTests.swift (relaunch, diagnostics privacy, search, integrity)
Apps/projectM-iOS/UITests/PresetNoteUITests.swift
scripts/check_compliance.py (+ test in scripts/test_scripts.py)
```

**Structure Decision**: follow PRE-016 (map keyed by preset ID, lenient body, own backup record) and PRE-008
(migration table).

## Complexity Tracking

None.
