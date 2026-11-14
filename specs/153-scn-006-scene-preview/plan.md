# Implementation Plan: SCN-006 Scene Preview Image

**Branch**: `feature/scn-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/153-scn-006-scene-preview/spec.md`

## Summary

A scene's preview is a still of the live output, captured through REC-001's frame grab when the scene
is saved or first applied, and stored in a cache that reuses PRE-001/PRE-002's design and code.

Package (`Packages/PresetLibrary/Sources/PresetLibrary/Thumbnails/`, Foundation only, Linux-tested):

- `ScenePreviewStore.swift` (new): `ScenePreviewKey` (scene ID, content hash, format version; stable
  ID and file name like `PresetThumbnailKey`; `contentHash(of:)` = SHA-256 hex via LocalPortability)
  and the `ScenePreviewStore` actor over `Library/Caches/ScenePreviews`. It reuses
  `PresetThumbnailIndex` unchanged (the entry's `presetID` field holds the scene ID, its
  `rendererVersion` the preview format version): open-time repair (`openRepairing`), `staleIDs`,
  `unlistedIDs` and `removeEntries` (internal, same module). Operations: `store(_:for:)` (write the
  PNG, add the entry, drop the scene's other hashes), `cachedURL(for:)`, `hasPreview(for:)`,
  `invalidate(sceneID:keepingContentHash:)`, `retainOnly(_:)`. Research SCN-006-D1, D2.
  PRE-001's cache, index and tests are not changed.

App:

- `ScenePreviewModel.swift` (new, main actor, `@Observable`): the store, the scenes' current hashes,
  an NSCache of decoded images, a `revision` counter rows observe, the pending capture (one at a
  time) and the injected `ScenePreviewCapturing` (`capture() async -> Data?`, an encoded PNG).
  `sceneSaved`, `sceneApplied` (1 s settle via injected sleep, checks per SCN-006-R3),
  `scenesChanged(_:)` (rehash the named scenes, `invalidate`), `reconcile(listing:)` (launch and
  cue removal: `retainOnly`), `image(forScene:)`.
- `ScenePreviewCapture.swift` (new): `LiveScenePreviewCapture` (asks the shown visual's
  `FrameCaptureSource` for its next frame with a 1 s timeout, converts with
  `FrameColorConversion.rgba8`, centre-crops and scales to 192 × 108 with Core Graphics, encodes PNG
  with PRE-001's `PNGThumbnailEncoder`), and the DEBUG `FixtureScenePreviewCapture`
  (`-uitestScenePreviewFixture`). Research SCN-006-D3, D4.
- `ShowCoordinator`: a `sceneFilesChanged: ((Set<String>) -> Void)?` hook called after Add, Rename,
  Duplicate and cue removal (with the touched scene IDs; removal passes the removed ones), and
  `sceneContentHashes()` for the listing. No behaviour change otherwise.
- `AppCoordinator+ScenePreviews.swift` (new): creates the model, wires the hook, the apply path
  (`connectShow`'s `applyScene` → `sceneApplied`), Add Current Scene (`sceneSaved`) and the launch
  reconciliation. AppCoordinator itself gets one stored property and one call in `connectShow`.
- `ScenePreviewView.swift` (new): the decorative 64 × 36 tile (image or placeholder), identifiers
  `scenePreview:<sceneID>` / `scenePreviewPlaceholder:<sceneID>`, `.accessibilityHidden(true)`.
- `SceneSwitcherView` and `SceneFoldersView`: the tile at the row's leading edge (Folders: in place of
  the `rectangle.stack` icon). Labels, values, actions and identifiers unchanged.
- No new UserDefaults key (the DEBUG flag is a launch argument), no networking.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/scene-preview.md](contracts/scene-preview.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PresetLibrary (+ LocalPortability), Compositor's FrameCapture (already used by
the app). None new.

**Storage**: `Library/Caches/ScenePreviews` (`index.json` + `<stableID>.png`), excluded from backup.

**Testing**: XCTest. PresetLibrary package tests on host and Linux (`ScenePreviewStoreTests`); app unit
tests (`ScenePreviewAcceptanceTests` with an injected capture and sleep); one UI test
(`ScenePreviewUITests`, under 30 s) on the feature's simulator "SCN6".

**Target Platform**: iOS 26+ (app), macOS 15 and Linux (package).

**Performance Goals**: one frame read-back per first apply of a file; encoding off the main actor;
hashing a few-KB scene file per change. No wall-clock assertions.

**Constraints**: Linux build of PresetLibrary; type-check budget; short tests (owner rule 7); one
pending frame request at a time (never while a Save Frame runs).

**Scale/Scope**: three new app files and one view, one new package file; small edits to
ShowCoordinator, AppCoordinator (+Show), SceneSwitcherView, SceneFoldersView.

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: Core Graphics, ImageIO, SwiftUI, Foundation; no networking. |
| VI. Modular boundaries | Pass: the cache in PresetLibrary (Foundation only, Linux-tested); the app captures and draws. |
| VII. Real-time audio safety | Pass: nothing on the audio thread. |
| IX. Pinned dependencies | Pass: none added. |
| X. Evidence-based quality | Pass: automated tests; simulator results are not device evidence; no device claim. |
| Privacy constraints | Pass: local Caches only, excluded from backup, cleared by Clear Caches; no new UserDefaults keys; pictures never leave the device. |

Post-design re-check: unchanged.

## Project Structure

```text
specs/153-scn-006-scene-preview/  spec, plan, research, data-model, contracts/scene-preview.md, quickstart, tasks
Packages/PresetLibrary/Sources/PresetLibrary/Thumbnails/ScenePreviewStore.swift   (new)
Packages/PresetLibrary/Tests/PresetLibraryTests/ScenePreviewStoreTests.swift      (new)
Apps/projectM-iOS/Coordinators/ScenePreviewModel.swift                           (new)
Apps/projectM-iOS/Coordinators/ScenePreviewCapture.swift                         (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+ScenePreviews.swift                (new)
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift                             (change hook, hashes)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                              (one property, one call)
Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift                         (apply and save calls)
Apps/projectM-iOS/Views/ScenePreviewView.swift                                   (new)
Apps/projectM-iOS/Views/SceneSwitcherView.swift                                  (tile in rows)
Apps/projectM-iOS/Views/SceneFoldersView.swift                                   (tile in scene rows)
Apps/projectM-iOS/Tests/ScenePreviewAcceptanceTests.swift                        (new)
Apps/projectM-iOS/UITests/ScenePreviewUITests.swift                              (new)
```

## Complexity Tracking

None.
