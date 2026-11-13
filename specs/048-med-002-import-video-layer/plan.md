# Implementation Plan: MED-002 Import Video Layer

**Branch**: `feature/med-002` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/048-med-002-import-video-layer/spec.md`

## Summary

The viewer picks one video with the system Photos picker (`PhotosPicker`, `.videos`, out of process,
no library permission) or the Files picker (`fileImporter`, movie types). The app copies it into
`Application Support/Videos/` through the new `VideoLayer` target's importer: the picked file is
checked (≤ 500 MB; a video track; H.264 or HEVC; ≤ 4096 px; ≤ 60 fps; the first picture decodes)
and remuxed without re-compression into a new QuickTime movie holding only the video track
(`AVMutableComposition` + `AVAssetExportSession` passthrough): no soundtrack, no metadata. The
identifier is a UUID in the settings key `settings.video.id`. A new `Video` visual (persisted) hosts
a CMP-001 compositor with a CMP-002 stack: the video layer (`VideoLayerSource`) at the bottom, the
circular spectrum on top.

Playback is pull-based and deterministic: a background decode thread runs an `AVAssetReader`
(BGRA output) and wraps each picture as a Metal texture through a `CVMetalTextureCache`
(`.bgra8Unorm_srgb`, so sampling returns linear light); pictures go into a **bounded queue of at
most 3**, guarded by a counting semaphore (the decoder blocks when the queue is full). The layer's
`render` advances a **playback clock** by the frame context's presentation-time differences (a gap
> 1 s advances nothing), takes the latest queued picture whose timestamp ≤ the playback time,
drops older ones (counted), and draws it with aspect fill and the video's rotation. At the end of
the file the decoder reopens the reader at 0 with a loop offset, so the timeline continues. When
the playback time runs > 1 s ahead of the decoder, the decoder reopens at the playback time (a
seek) instead of decoding everything in between. The queue, clock and scheduler are plain Swift
(Linux shape); AVFoundation, CoreVideo and Metal compile out there.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 in CI: explicit closure types)

**Primary Dependencies**: AVFoundation (`AVURLAsset`, `AVAssetReader`, `AVMutableComposition`,
`AVAssetExportSession`), CoreVideo (`CVMetalTextureCache`), CoreMedia, Metal (layer); PhotosUI
(`PhotosPicker`) and SwiftUI `fileImporter` (app only); test fixtures with `AVAssetWriter`

**Storage**: one file in `Library/Application Support/Videos/<uuid>.mov`; the identifier in
UserDefaults (`settings.video.id`, an FR-065 "user setting")

**Testing**: XCTest: Compositor package tests (host macOS, iOS 27.2 simulator; Linux shape with
`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`), app unit tests, one UI test.
Fixtures are generated in the tests (64 × 48, 30 fps, 2 s, each frame a solid color encoding its
index); no media is checked in.

**Target Platform**: iOS/iPadOS 26.0+ (ADR-0002); package code also builds on macOS 15 and Linux

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: per frame no decode, I/O or unbounded lock (CMP-001 contract); at most 3
decoded pictures plus the one shown (4K BGRA ≈ 4 × 35 MB worst case); decoding sleeps while the
queue is full (pause) and stops in the background

**Constraints**: no network (FR-068), public APIs only, no photo library permission, no
required-reason API (file size is read with `.fileSizeKey`, not a timestamp or disk-space API)

**Scale/Scope**: one stored video; ~9 new package source files, ~5 app files, ~4 test files

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | PhotosUI, SwiftUI `fileImporter`, AVFoundation, CoreVideo, Metal; nothing private, no `dlsym` | Pass |
| VI. Modular boundaries | `VideoLayer` imports Compositor and CameraLayer (its rotation and fill geometry), AVFoundation, CoreVideo, Metal; no projectM, ANGLE, capture or app code. The app owns storage, settings and pickers. | Pass |
| VII. Real-time audio safety | No audio path change; the video's soundtrack is dropped, the analyzer is the existing one | Pass |
| VIII. Upstream fidelity | projectM untouched | Pass |
| X. Evidence | Host and simulator tests with generated fixtures and a fake clock; real pickers, HEVC/H.264 from devices, 4K60, long files and thermal state are `{device}` tasks left open | Pass |
| Security (untrusted imports) | Size, track, codec, size and rate checks before the copy; first-picture decode; damaged data → typed error; decoder boundary for MED-014 | Pass |
| Privacy | Privacy review in the spec; no permission; copy without metadata or soundtrack; removable; privacy policy and App Privacy notes updated | Pass |
| FR-068 (no networking) | No networking API; compliance check runs | Pass |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/048-med-002-import-video-layer/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/video-layer.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/Compositor/
├── Package.swift                         # + target VideoLayer (deps Compositor, CameraLayer)
├── Sources/VideoLayer/
│   ├── VideoImportLimits.swift           # limits, VideoImportError, VideoCodec (plain Swift)
│   ├── VideoTrackInfo.swift              # size, rotation, rate, duration, codec (plain Swift)
│   ├── VideoPlaybackClock.swift          # playback time from presentation time (plain Swift)
│   ├── VideoFrameQueue.swift             # bounded queue + decode pipeline, generic (plain Swift)
│   ├── VideoLayerKind.swift              # LayerKind.video
│   ├── VideoFrameReading.swift           # the decoder seam (protocol) (plain Swift)
│   ├── AVVideoProbe.swift                # import checks (AVFoundation)
│   ├── VideoSanitizer.swift              # remux: video track only, no metadata (AVFoundation)
│   ├── AVVideoFrameReader.swift          # AVAssetReader → CVMetalTexture (AVFoundation + Metal)
│   └── VideoLayerSource.swift            # the CMP-001 layer (Metal)
└── Tests/CompositorTests/
    ├── VideoFrameQueueTests.swift        # fake reader + fake clock (Linux too)
    ├── VideoPlaybackClockTests.swift     # (Linux too)
    ├── VideoFixtures.swift               # AVAssetWriter fixture generator
    ├── VideoImportTests.swift            # probe, limits, remux privacy (AVFoundation)
    └── VideoLayerTests.swift             # through the real compositor (Metal)

Apps/projectM-iOS/
├── Coordinators/VideoStore.swift, VideoCoordinator.swift, AppCoordinator.swift, AppSettings.swift
├── Visuals/VideoVisualHost.swift
├── Views/SettingsView.swift, VisualizerView.swift (+ diagnostics labels)
├── Debug/UITestVideoFixture.swift        # DEBUG: -uitestSeedVideo
├── Tests/VideoStoreTests.swift
└── UITests/VideoLayerUITests.swift
```

**Structure Decision**: a new `VideoLayer` target in the Compositor package beside `ImageLayer`,
reusing `CameraLayer`'s `CameraRotation` and `CameraPictureGeometry` (aspect fill with rotation)
instead of copying them. App files mirror MED-001's Photo files.

## Complexity Tracking

| Choice | Why | Simpler alternative rejected because |
|---|---|---|
| `VideoVisualHost` repeats `PhotoVisualHost`'s frame loop; `VideoStore`/`VideoCoordinator` repeat the photo ones | Keeps MED-001's verified code untouched while it is fresh; the differences (decoder stop in background, frame diagnostics, async import) are real | A generic media host now would change Photo's verified paths in a row that is not about Photo; a later refactor can merge them once MED-006/MED-008 add more media kinds |
| A separate decode thread with a semaphore | The only way to keep decoding off the frame loop with a hard bound | `AVPlayerItemVideoOutput` paces to a player clock (not injectable, so not deterministic in tests) and owns its own buffering |
