# Implementation Plan: MED-013 Media Asset Relinking

**Branch**: `feature/med-013` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/146-med-013-media-relinking/spec.md`

## Summary

Missing media is found from the saved scenes, shown as a placeholder tile when a cue applies such a
scene, and restored either by checksum (FILE-008's registry plus a bounded list of released hashes, a
re-import or a folder scan) or by replacement (a new identifier written into every scene, all or
nothing). Research: [research.md](research.md); contract: [contracts/media-relink.md](contracts/media-relink.md).

Packages (Foundation only, tested on the host and in CI on Linux):

- `LocalPortability/ContentAddressedMediaFolder.swift`: the registry file keeps an optional `released`
  list; `release` records removed entries. New `ContentAddressedMediaFolder+Relink.swift`:
  `knownPayloadName(of:)`, `adoptKnown(_:)`, `restorePayload(from:wanted:)`, `forget(_:)`.
- `LocalPortability/MediaFolderScan.swift` (new): the bounded, read-only folder scan.
- `SceneFormat/SceneMediaReferences.swift` (new): `SceneDocument.mediaReferences` and
  `replacingMediaReference(store:from:to:)` (photo, slides, logo, video).
- `ShowControl/ShowStorage/ShowMediaRelink.swift` (new): `ShowStore.mediaUsage()` and the atomic
  `rewriteMediaReferences(store:from:to:fault:)`.
- `LibraryBackup/LibraryEraser.swift`: a scenes-only erase also forgets the released identifiers.

App (`Apps/projectM-iOS`):

- `Coordinators/MediaRelinkService.swift` (new, nonisolated): missing list, checksum relink, folder scan,
  replacement (photo or video import, scene rewrite, settings rewrite, discard on failure).
- `Coordinators/MissingMediaCoordinator.swift` (new, main actor, observable): items, busy state, last
  report, placeholder; announces on the library lane.
- `Coordinators/AppCoordinator+MissingMedia.swift` (new): wiring (import callbacks, show apply).
- `Views/MissingMediaView.swift` (new): the Missing Media screen and the placeholder tile.
- Small edits: `StorageUsageView` (a link row), `SettingsView` (pass the coordinator), `VisualizerView`
  (one tile line), `AppCoordinator` (one property, one connect call), `AppCoordinator+Show` (placeholder
  on apply), `scripts/check_status_events.py` (register the new view).
- DEBUG: `Debug/UITestMissingMediaFixture.swift` (`-uitestMissingMediaSeed`).

## Technical Context

Swift 6.4 / Xcode 27.2, iOS 26+. No new dependencies, no networking, no new UserDefaults keys.
Testing: XCTest in packages (host), app-hosted unit tests and one XCUITest on simulator "MED13".

## Constitution Check

- I Public APIs only: `FileManager`, security-scoped URLs, `NSFileCoordinator`, SwiftUI `fileImporter`.
- V Privacy: local only; the released list holds names, never bytes; erase removes it.
- VI Modular boundaries: format and store logic in packages; the app wires.
- X Evidence: simulator tests only; no device claim.

## Project Structure

```text
specs/146-med-013-media-relinking/
├── spec.md  plan.md  research.md  data-model.md  quickstart.md  tasks.md
├── contracts/media-relink.md
└── checklists/requirements.md
```

## Complexity Tracking

None.
