# Implementation Plan: PRE-018 Preset integrity scanner

**Branch**: `feature/pre-018` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A user-started check of the user library. The pure scanner (`PresetIntegrityScanner`) and its model
live in the `PresetLibrary` package (Foundation only, Linux-testable). `UserPresetLibrary` (an actor, so
off the main thread) gains a bounded **inventory** of its records (file present and matching by size and
SHA-256, static re-check with the bundled texture names), a checksum **relink** that writes a record's
bytes back, and a user **quarantine** (`movedByUser`). The app copies the five reference stores into a
`PresetReferenceSnapshot` on the main actor, runs the inventory and the scanner off main, and shows the
report in a Library Check screen reached from My Presets. Fixes go through the existing stores; Fix All
Safe removes dangling references only. Results are announced on the library lane.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 / Swift 6.4.2; CI also Xcode 26)
**Primary Dependencies**: Foundation; LocalPortability (SHA-256 via `ContentHash`); SwiftUI in the app
**Storage**: none new. Reads `UserPresets/`, `PresetCollections/{tags,overrides,collections}.json`, the
`favorites` and `recentPresets` UserDefaults keys; fixes write through their existing stores.
**Testing**: XCTest — `swift test --package-path Packages/PresetLibrary` (host, Linux-clean), app unit
tests (acceptance) and one XCUITest on simulator "PRE18 iPhone 17" (iOS 27.2)
**Target Platform**: iOS/iPadOS 26+
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: a 1,000-preset library scans in a few seconds off main; the main actor only copies
the reference lists (≤ 60,000 strings)
**Constraints**: bounds of R14; type-check budget; unit tests ≤ 10 s; UI test < 30 s
**Scale/Scope**: ≤ 1,200 user preset records, ≤ 60,000 references, ≤ 500 issues

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pass — Foundation/SwiftUI only. |
| VI Modular boundaries | Pass — scanning, relink and quarantine logic in `PresetLibrary`; the app wires stores and shows the report. |
| VII Real-time audio safety | Pass — nothing on the audio or render path. |
| VIII Upstream fidelity | Pass — no engine change; texture rules mirror the existing validator. |
| IX Untrusted input | Pass — stored text is re-read with the same bounded validator; files over the size limit are not read; a relink accepts only bytes whose checksum the record already names. |
| X Evidence | Package unit tests, app acceptance test, simulator UI test (not device evidence; no device claim). |
| Privacy | Pass — no network, no new key or file, nothing about scans stored. |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/194-pre-018-integrity-scanner/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/library-integrity.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/PresetLibrary/Sources/PresetLibrary/Integrity/
├── PresetIntegrityModel.swift        # issue, kind, store, action, report, limits, words
├── PresetReferenceSnapshot.swift     # the five stores' preset IDs, copied at scan time
├── PresetIntegrityScanner.swift      # pure scan(inventory, references, isBuiltIn, limits)
└── UserPresetLibrary+Integrity.swift # inventory, relink by checksum, quarantine by user
Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/UserPresetStore.swift   # restoreContents
Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/UserPresetModel.swift   # movedByUser reason
Packages/PresetLibrary/Sources/PresetLibrary/RecentPresetHistory.swift           # removing(ids)
Packages/PresetLibrary/Tests/PresetLibraryTests/PresetIntegrity*Tests.swift
Apps/projectM-iOS/Coordinators/LibraryIntegrityCoordinator.swift
Apps/projectM-iOS/Coordinators/PresetCoordinator+Integrity.swift   # snapshot + reference removal
Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift        # `library` internal, integrity hooks
Apps/projectM-iOS/Coordinators/PresetCoordinator.swift             # favorites/collections stores internal
Apps/projectM-iOS/Coordinators/RecentPresetsStore.swift, RecentPresetsCoordinator.swift  # remove ids
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                # construction, lane, DEBUG seed
Apps/projectM-iOS/Views/LibraryCheckView.swift
Apps/projectM-iOS/Views/UserPresetsView.swift, PresetBrowserView.swift   # row + route
Apps/projectM-iOS/Debug/UITestBrokenLibraryFixture.swift
Apps/projectM-iOS/Tests/LibraryIntegrityAcceptanceTests.swift
Apps/projectM-iOS/UITests/LibraryCheckUITests.swift
```

**Structure Decision**: pure logic in the package (as PRE-012/PRE-016), the app owns the stores that
are app-only (favorites, recents) and the screen; MED-013's relink-by-checksum pattern for files.

## Complexity Tracking

None.
