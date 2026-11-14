# Implementation Plan: PRE-005 Preset Energy Facets

**Branch**: `feature/pre-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/221-pre-005-energy-facets/spec.md`

## Summary

The PRE-001 thumbnail drawing reads back three frame samples (the thumbnail plus two earlier frames) with the
engine clock pinned to the frame number; a deterministic integer scorer turns them into a motion score that is
written into the thumbnail PNG. Rows learn the score on their existing decode (as PRE-004 learns colours), keep
it in a versioned index in Caches, and the browser offers Calm / Moderate / Energetic chips that combine with
tags, colours, Favorites and search.

- **ProjectMBridge**: `ProjectMEngine.setFrameTime(_:)` wraps the public `projectm_set_frame_time` (no engine patch).
- **Rendering**: `PresetThumbnailDrawing.drawSamples(…, sampleFrames:…)` with a default implementation (final
  frame only), so existing fakes keep compiling; `PresetThumbnailSampleResult`.
- **ANGLERendering**: `PresetThumbnailRunner` implements `drawSamples`: pins the frame time to `n / 60` s, reads
  back the requested frames (flipped like the thumbnail).
- **PresetLibrary** (Foundation only, Linux-tested): `PresetEnergy`, `PresetMotionScore` (fixed 32 × 18 grid,
  integer luma, thresholds), `PresetMotionPNG` (tEXt chunk write and read with CRC-32), `PresetMotionIndex`
  (schema 1, score version 1, open-time repair), `PresetMotionStore` (actor; coalesced save, invalidate,
  retainOnly) and `PresetEnergyFilter` (OR within classes, counts).
- **App**: `RendererThumbnailRenderer` asks for samples, scores them and embeds the score; the DEBUG
  `FixtureThumbnailRenderer` embeds a deterministic fixture score; `PresetThumbnailModel` learns scores on the
  decode task (mirror, store, launch load and prune, PRE-002 invalidation); `PresetCoordinator+Energy` holds the
  selection and joins `filterMatches`; `PresetEnergyChipRow` sits under the colour chips.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Objective-C++ bridge; Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new. The engine's public C API (`projectm_set_frame_time`).

**Storage**: `Library/Caches/PresetMotion/motion.json` (excluded from backup; FILE-009 "Caches"; FILE-010 Clear
Caches); the score's tEXt field inside each thumbnail PNG. No UserDefaults key.

**Testing**: XCTest. PresetLibrary on the host (Linux in CI); one ANGLERendering test on the private simulator;
app unit tests and one UI test on "PRE5 iPhone 17" (iOS 27.2). Injected sleep for the coalesced save.

**Target Platform**: iOS/iPadOS 26+; package also macOS 15 and Linux.

**Performance Goals**: two extra GPU waits and 36 KB read-backs per thumbnail (well under the ~1 s drawing);
1,152 grid samples per score; at most one index write per second.

**Constraints**: type-check budget; small edits to shared files (`PresetBrowserView`, `PresetCoordinator`,
`PresetCoordinator+Colors`).

**Scale/Scope**: up to 12,847 entries of about 70 bytes.

## Constitution Check

- I Public APIs only: Foundation, SwiftUI, ImageIO (existing encoder). Pass.
- VI Modular boundaries: scoring, PNG field, index and filter in PresetLibrary (Foundation only); drawing in ANGLERendering. Pass.
- VII Real-time audio safety: no audio path touched; thumbnail thread at utility priority. Pass.
- VIII Upstream fidelity: the frame clock uses the engine's documented public API; no engine change. Pass.
- Privacy/local-first: local cache file; no network; no new stored setting. Pass.
- X Evidence-based quality: deterministic fixtures and pinned scores; simulator results are not device evidence; thresholds marked provisional. Pass.

Post-design re-check: unchanged, pass. No ADR: no constitution or project default is overridden.

## Project Structure

```text
Packages/ProjectMBridge/Sources/ProjectMBridge/include/PMBridge.h, PMBridge.mm              (setFrameTime)
Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift                                 (drawSamples)
Packages/ANGLERendering/Sources/ANGLERendering/PresetThumbnailRunner.swift                    (samples, clock)
Packages/ANGLERendering/Tests/ANGLERenderingTests/PresetThumbnailRunnerTests.swift            (S3)
Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetEnergy.swift                        (new)
Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetMotionScore.swift                   (new)
Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetMotionPNG.swift                     (new)
Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetMotionIndex.swift                   (new)
Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetMotionStore.swift                   (new)
Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetEnergyFilter.swift                  (new)
Packages/PresetLibrary/Tests/PresetLibraryTests/PresetEnergyFacetTests.swift                  (new; S1, S2)
Packages/PresetLibrary/Tests/PresetLibraryTests/ThumbnailFixtures/motion-*.json               (new)
Apps/projectM-iOS/Coordinators/PresetThumbnailModel.swift                                     (scores)
Apps/projectM-iOS/Coordinators/AppCoordinator+Thumbnails.swift, PresetCoordinator.swift       (wiring)
Apps/projectM-iOS/Coordinators/PresetCoordinator+Energy.swift                                 (new)
Apps/projectM-iOS/Coordinators/PresetCoordinator+Colors.swift                                 (filterMatches joins energy)
Apps/projectM-iOS/Views/PresetEnergyChips.swift                                               (new)
Apps/projectM-iOS/Views/PresetBrowserView.swift                                               (row placement)
Apps/projectM-iOS/Tests/PresetEnergyFacetAppTests.swift                                       (new; S4)
Apps/projectM-iOS/UITests/PresetEnergyFacetUITests.swift                                      (new; S5)
```

## Complexity Tracking

None.
