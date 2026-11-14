# Implementation Plan: PRE-001 Visual Thumbnail Cache

**Branch**: `feature/pre-001` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/132-pre-001-thumbnail-cache/spec.md`

## Summary

Every playable preset row in the browser gets a small picture. A Foundation-only cache in the
`PresetLibrary` package (Linux-testable) keys each thumbnail by a stable ID (SHA-256 of preset ID,
content hash and renderer version), keeps a versioned JSON index in `Library/Caches/PresetThumbnails`,
serves hits without rendering, and queues misses (newest first, at most 32 waiting, cancellable,
one at a time with a 150 ms pause). Rendering sits behind a protocol: tests and Linux use a counting
fake; the app uses a new `PresetThumbnailRunner` in `ANGLERendering` that draws the preset off screen
(own thread, unshared EGL context, own engine, 128 × 72 target, 45 frames of seeded synthetic audio,
the `PresetTrialRunner` pattern) and reads the pixels back; the app encodes PNG with ImageIO.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the Mac Studio; CI also Xcode 26)

**Primary Dependencies**: Foundation, LocalPortability (`PortableSHA256`), ANGLE/EGL + ProjectMBridge (app renderer), ImageIO/CoreGraphics (PNG), SwiftUI

**Storage**: PNG files plus `index.json` in `Library/Caches/PresetThumbnails` (excluded from backup)

**Testing**: XCTest: `swift test --package-path Packages/PresetLibrary` (host and Linux); app unit tests and one UI test on the own simulator "PRE1 iPhone 17" (iOS 27.2)

**Target Platform**: iOS/iPadOS 26+; the package also builds on Linux

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: no visible frame-rate cost (S7 on D1, `{device}`); the main thread only decodes a 128 × 72 PNG per row

**Constraints**: no wall-clock assertions (injected sleep); unit tests ≤ 10 s, package suite < 1 min, UI test < 30 s

**Scale/Scope**: lazily, only rows shown; up to 12,847 bundled presets plus user presets over time

## Constitution Check

| Principle | Check |
|---|---|
| I. Public Apple APIs only | EGL/GLES through the existing ANGLE bridge, ImageIO, FileManager, SwiftUI. No private API. PASS |
| VI. Modular boundaries | The cache knows no renderer (protocol `PresetThumbnailRendering`); the renderer interface (`PresetThumbnailDrawing`) lives in `Rendering` beside `PresetTrialing`; the ANGLE runner knows nothing of the cache. PASS |
| VII. Real-time audio safety | No audio path involved: the thumbnail audio is synthetic, generated off the audio thread. PASS |
| VIII. Upstream fidelity | No engine change; uses the public bridge (`loadPresetData`, `addPCMInterleavedStereo`, `renderFrame`). PASS |
| X. Evidence | Package and simulator tests for logic and UI; the frame-rate cost is a `{device}` task, never claimed from the simulator. PASS |
| Security (untrusted imports) | Only playable user presets (passed PRE-012's trial) are rendered; locked, waiting and quarantined presets never. PASS |
| Privacy | Pictures stay in Caches, no network, no audio recorded. PASS |

Post-design re-check: unchanged, PASS.

## Project Structure

### Documentation (this feature)

```text
specs/132-pre-001-thumbnail-cache/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/thumbnail-cache.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/PresetLibrary/Sources/PresetLibrary/Thumbnails/
├── PresetThumbnailSpec.swift        # size, frames, seed, renderer version; SyntheticPCM
├── PresetThumbnailKey.swift         # stable ID and file name
├── PresetThumbnailIndex.swift       # versioned index, load-and-repair (migrations)
└── PresetThumbnailCache.swift       # actor: hits, bounded LIFO queue, cancellation, throttle
Packages/PresetLibrary/Tests/PresetLibraryTests/
├── PresetThumbnailCacheTests.swift
└── ThumbnailFixtures/               # renderer-v0, schema-v99, corrupt, missing-file indexes
Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift   # PresetThumbnailDrawing + presetThumbnails
Packages/ANGLERendering/Sources/ANGLERendering/PresetThumbnailRunner.swift
Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift      # owns, suspends, shuts down the runner
Apps/projectM-iOS/Coordinators/PresetThumbnailModel.swift      # cache + contents + PNG adapter + image memory
Apps/projectM-iOS/Views/PresetThumbnailView.swift              # placeholder / image
Apps/projectM-iOS/Views/PresetBrowserView.swift                # PresetRow shows it
Apps/projectM-iOS/Coordinators/PresetCoordinator.swift         # `thumbnails` property
Apps/projectM-iOS/Coordinators/AppCoordinator.swift            # creates the model (one line)
Apps/projectM-iOS/Tests/PresetThumbnailModelTests.swift
Apps/projectM-iOS/UITests/PresetThumbnailUITests.swift
```

**Structure Decision**: logic in the Linux-tested package, rendering in `ANGLERendering`, glue and
views in the app, following PRE-012's trial split.

## Complexity Tracking

None.
