# Implementation Plan: REC-010 Recording library

**Branch**: `feature/rec-010` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/198-rec-010-recording-library/spec.md`

## Summary

Recordings become keepable: the REC-012 "Recording ready" panel gains **Keep**, which moves the offered
temporary file into `Application Support/RecordingLibrary` (a rename on one volume). Settings › Storage gains a
**Recordings** screen that scans that folder (no index), lists the files newest first with a cached thumbnail
(frame at 1 s) and the facts of a quick header read (duration, size, date, resolution, frame rate, codec), and
offers Play (AVKit player, local file), Share… (REC-012's `ActivitySharePresenter`, same excluded activities),
Rename (validated, extension kept) and Delete with a confirmation. Delete removes the file and the row in one
main-actor update, so the count and total drop at once; the thumbnail cache entry goes too. Unreadable files are
"Incomplete" with Delete only.

FILE-009 gets a "Saved recordings" category (not cleanable, so FILE-010 protects it automatically) and the old
temporary category reads "Unsaved recordings"; FILE-011 gets a "Saved recordings" erase category. The library is
not part of the FILE-005 backup.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 build machine; CI also Xcode 26).
**Primary Dependencies**: SwiftUI, AVFoundation (`AVURLAsset`, `AVAssetImageGenerator`), AVKit (`VideoPlayer`), ImageIO-free JPEG via UIKit; existing LocalPortability and LibraryBackup packages.
**Storage**: files only (`Application Support/RecordingLibrary`, `Caches/RecordingThumbnails`); no new UserDefaults key, no index.
**Testing**: LocalPortability and LibraryBackup package tests (host, under 1 min); app unit tests on the REC10 iOS 27.2 simulator with recordings generated at test time (AVAssetWriter, 64×64 H.264); one UI test (< 30 s) with a DEBUG seed.
**Target Platform**: iOS/iPadOS 26+.
**Project Type**: mobile app with SwiftPM packages.
**Performance Goals**: the scan reads directory entries and resource values only; facts and thumbnails load off the main thread per visible row, cached by name and size.
**Constraints**: Constitution I, IV, VI, X; no networking (`check_network_symbols`); no Photos permission (`check_permission_catalog.py`); FileTimestamp C617.1 (dates of files inside the container) is already declared; ACC-004 announcer lanes; owner rule 7; LocalPortability and LibraryBackup stay Linux-buildable.
**Scale/Scope**: four new app files (store, inspector, model, view) plus a DEBUG fixture; one case each in two package enums; small hooks in VideoRecordingCoordinator, CaptureResultPanels, StorageLocations, StorageUsageView, SettingsView, VisualizerView and AppCoordinator.

## Constitution Check

| Principle | Check |
|---|---|
| I. Public APIs only | Pass. FileManager, AVFoundation, AVKit, SwiftUI, UIActivityViewController. |
| IV. Truthful labeling | Pass. Facts are read from the file; an unreadable file says "Incomplete". |
| VI. Modular boundaries | Pass. Categories in the packages that own them; library logic in the app beside the REC-003 coordinator. |
| VII. Real-time safety | Pass. Nothing on the frame or audio path; Keep is a rename after the recording finished. |
| Privacy | Pass. Files stay in the container; they leave only through the share sheet the user opens; no permission or key added. |
| X. Evidence | Simulator tests on the Mac; a device check is `{device}`. |

Post-design re-check: Pass. No ADR: REC-003-R13 ("nothing outlives the session") still holds for every recording the user does not Keep; Keep is a new explicit user action, not a changed default.

## Project Structure

### Documentation (this feature)

```text
specs/198-rec-010-recording-library/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/recording-library.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/LocalPortability/Sources/LocalPortability/StorageUsage.swift     # .savedRecordings, titles
Packages/LibraryBackup/Sources/LibraryBackup/LibraryErasePolicy.swift     # .recordings erase category
Packages/LibraryBackup/Sources/LibraryBackup/LibraryEraseInventory.swift  # its count
Apps/projectM-iOS/
├── Coordinators/RecordingLibraryStore.swift       # NEW: scan, order, keep, delete, rename, name rules
├── Coordinators/RecordingLibraryInspector.swift   # NEW: header facts, thumbnails, cache
├── Coordinators/RecordingLibraryModel.swift       # NEW: observable list, delete confirmation, announcements
├── Views/RecordingLibraryView.swift               # NEW: the screen and rows
├── Debug/RecordingLibraryFixture.swift            # NEW: generated test recordings, -uitestRecordingLibrarySeed
├── Coordinators/VideoRecordingCoordinator.swift   # keepOffered()
├── Views/CaptureResultPanels.swift                # Keep button
├── Coordinators/StorageLocations.swift            # .savedRecordings root
├── Views/StorageUsageView.swift                   # Recordings link, kept note
├── Views/SettingsView.swift, VisualizerView.swift, Coordinators/AppCoordinator.swift   # wiring (one line each)
├── Tests/RecordingLibraryAcceptanceTests.swift    # NEW
└── UITests/RecordingLibraryUITests.swift          # NEW
```

**Structure Decision**: the library lives in the app next to the REC-003 coordinator (it needs AVFoundation and
the app's folders); only the category enums change in the packages.

## Complexity Tracking

None.
