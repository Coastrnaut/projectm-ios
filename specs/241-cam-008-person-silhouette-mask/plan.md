# Implementation Plan: CAM-008 Person Silhouette Mask

**Branch**: `feature/cam-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Add a "Person mask" choice (Off/Person/Background) to Settings › Camera. On-device person
segmentation (Vision, behind `PersonSegmenting`) runs on the camera's pictures at a bounded rate in a
`PersonMasker`; its newest mask is uploaded by `CameraLayerSource` into a small r8 texture ring and
multiplied into the camera layer's coverage in the existing camera shader, sampled with the same
coordinates as the picture so rotation, mirror and crop follow. Unsupported, failed or paused
segmentation draws the Off picture and the row explains why. Plain-Swift policy, schedule and value
types build on Linux.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26)
**Primary Dependencies**: Vision (`VNGeneratePersonSegmentationRequest`), CoreVideo, Metal, SwiftUI
**Storage**: one UserDefaults key `settings.camera.personMask`; masks memory only
**Testing**: XCTest: `Packages/Compositor` (`PersonMaskTests`, `PersonMaskLayerTests`), app unit tests (`CameraPersonMaskTests`), one XCUITest file
**Target Platform**: iOS 26+; plain-Swift parts on Linux (`COMPOSITOR_NO_METAL`)
**Performance Goals**: at most one analysis per two camera pictures, none in flight twice; render never waits
**Constraints**: public APIs; no network; no new permission; masks never stored
**Scale/Scope**: 3 new package files, layer/shader edit, provider hooks, 1 row view, small host/coordinator/settings edits

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Vision person segmentation, CoreVideo, Metal: public. |
| VI Modular boundaries | Segmenter behind a protocol; camera layer has no Vision import; the app picks the segmenter. |
| Privacy | On-device only; memory only; dropped on stop; ADR-0063. No new permission. |
| Photosensitivity | Mask flicker passes through the composite flash guard unchanged. |
| X Evidence | Simulator proves logic; person masking on D1 is `{device}` CAM-008-T16. |
| Short tests | Package tests < 1 s each; one UI test file < 30 s per test. |

Post-design re-check: no violations.

## Project Structure

```text
specs/241-cam-008-person-silhouette-mask/   spec, plan, research, data-model, contracts/person-mask.md, quickstart, tasks
docs/adr/0063-on-device-person-segmentation.md     NEW
Packages/Compositor/Sources/CameraLayer/
  PersonMask.swift            NEW plain Swift: mode, bitmap, quality, plan/policy, availability, schedule
  PersonSegmenting.swift      NEW Apple: protocol, VisionPersonSegmenter, FixturePersonSegmenter
  PersonMasker.swift          NEW Apple: bounded scheduler + newest-mask slot
  CameraLayerSource.swift     mask texture ring, uniforms, shader coverage term
  CameraFrameProvider.swift   `personMasker` hook (default none)
  AVCameraFrameProvider.swift offers pixel buffers
  StubCameraFrameProvider.swift offers its picture (CVPixelBuffer made once)
Packages/Compositor/Tests/CompositorTests/PersonMaskTests.swift, PersonMaskLayerTests.swift   NEW
Apps/projectM-iOS/
  Coordinators/AppSettings.swift      `cameraPersonMask` + key
  Visuals/CameraVisualHost.swift      masker, policy updates, `-uitestPersonSegmenter`
  Coordinators/AppCoordinator.swift   availability mirror, setting forwarding
  Views/CameraPersonMaskRow.swift     NEW row + coordinator extension
  Views/SettingsView.swift, Views/VisualizerView.swift   one line each
  Tests/CameraPersonMaskTests.swift, UITests/CameraPersonMaskUITests.swift   NEW
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift   key lists
```

## Complexity Tracking

None.
