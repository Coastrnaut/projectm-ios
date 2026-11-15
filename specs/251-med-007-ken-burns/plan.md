# Implementation Plan: MED-007 Image Ken Burns

**Branch**: `feature/med-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/251-med-007-ken-burns/spec.md`

## Summary

A photo (and every slideshow slide) can pan and zoom from a start crop rectangle to an end crop rectangle over a
duration with an easing, sampled on the injected frame clock; exact rectangles at the start and end.

- **Compositor** (plain Swift, Linux): `KenBurnsRect`, `KenBurnsEasing`, `KenBurnsMotion` (validation, clamping,
  presets, `crop(elapsedNanoseconds:durationNanoseconds:)` exact at both ends, monotonic between) and
  `KenBurnsPlayhead` (elapsed time from clamped frame durations, restart, finished). New file
  `Packages/Compositor/Sources/Compositor/KenBurns.swift`, beside `LayerFit`.
- **ImageLayer** (Metal): `ImageLayerSource.kenBurns` (`KenBurnsMotion?`), `reduceMotion`; the playhead restarts
  when the held picture changes; the crop becomes the fitted content (`ImagePictureGeometry(placement:crop:)`):
  `visible' = visible · size`, `offset' = origin + offset · size`, and the shader's transparent test uses the crop's
  bounds (a new `bounds` uniform). CMP-013: time dependency while moving, still (parameter generation) while holding.
- **SceneFormat**: `SceneKenBurns` as the optional `kenBurns` field of a `photo` asset (like MED-006's `slideshow`),
  `SceneAsset.photoKenBurns`.
- **App**:
  - `KenBurnsStore` (`settings.photo.kenBurns`, JSON) and `KenBurnsCoordinator` (`@Observable`: on/off, preset,
    custom zoom/position edits, duration, easing, scene value and restore, announcements).
  - `AppCoordinator+KenBurns.swift`: applies the movement to the photo layer (duration = slide dwell while the
    slideshow is active, Reduce Motion), called from `refreshPhotoContent`, the slideshow tick, the Reduce Motion
    change and every setting change.
  - Scene paths: `SceneInputs.kenBurns`, `SceneSlideshowRestore.kenBurns`, `SceneSlideshowBridge.photoAsset(…,
    kenBurns:)`; the five restore call sites use one helper `restorePhotoMotion`.
  - `KenBurnsSection` in Settings › Photo (`mediaSections`), accessible sliders via `.accessibleParameter`.
  - The key in `AppSettings.allKeys`, `LibrarySettingsPolicy.includedKeys`, `ALLOWED_KEYS`.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new (Metal, SwiftUI already used).

**Storage**: one UserDefaults key `settings.photo.kenBurns`; scene field `kenBurns` on the photo asset.

**Testing**: XCTest. Compositor model tests on the host (Linux shape in CI); GPU read-back tests in
CompositorTests (skipped without Metal); SceneFormat round trip; app unit tests and one UI test on the private
simulator "MED7 iPhone 17" (iOS 27.2). Frame times injected; no wall-clock assertions.

**Target Platform**: iOS/iPadOS 26+; packages also macOS 15 and Linux.

**Performance Goals**: per frame a few multiplies and one 48-byte uniform; no allocation; a finished or reduced
movement is cached like a still photo (CMP-013).

**Constraints**: exact start/end; monotonic; type-check budget; Linux build of Compositor and SceneFormat.

**Scale/Scope**: 1 model file, 1 layer change, 1 scene field, 1 Settings section, 1 setting key.

## Constitution Check

- I Public APIs only: Metal and SwiftUI public API. Pass.
- VI Modular boundaries: the movement model is plain Swift in Compositor; the layer applies it; the app only
  chooses values. Nothing imports projectM or capture. Pass.
- VII Real-time audio safety: no audio path touched. Pass.
- Privacy: one preference key, no new data leaves the device; no metadata from photos. Pass.
- Photosensitivity (FR-072 family): a slow pan/zoom of a still adds no flashes; the composite flash guard still sees
  every frame; slide changes keep MED-006's safety floor. Pass.
- X Evidence-based quality: GPU read-back against CPU references; device smoothness left as `{device}`. Pass.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/Compositor/Sources/Compositor/KenBurns.swift                                          (new)
Packages/Compositor/Sources/ImageLayer/ImageLayerSource.swift, ImagePictureGeometry.swift
Packages/Compositor/Tests/CompositorTests/KenBurnsModelTests.swift                             (new)
Packages/Compositor/Tests/CompositorTests/KenBurnsLayerTests.swift                             (new, GPU)
Packages/SceneFormat/Sources/SceneFormat/SceneKenBurns.swift                                   (new)
Packages/SceneFormat/Tests/SceneFormatTests/SceneKenBurnsTests.swift                           (new)
Apps/projectM-iOS/Coordinators/KenBurnsCoordinator.swift                                       (new; store inside)
Apps/projectM-iOS/Coordinators/AppCoordinator+KenBurns.swift                                   (new)
Apps/projectM-iOS/Views/KenBurnsSection.swift                                                  (new)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift, AppCoordinator+Slideshow.swift, AppCoordinator+Show.swift,
  AppCoordinator+SceneHistory.swift, SceneAutosaveCapture.swift, ShowSceneSnapshot.swift,
  SceneSlideshowBridge.swift, AppSettings.swift, Visuals/PhotoVisualHost.swift, Views/SettingsView.swift (small edits)
Apps/projectM-iOS/Tests/KenBurnsAppTests.swift                                                 (new)
Apps/projectM-iOS/UITests/KenBurnsUITests.swift                                                (new)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py,
  Apps/projectM-iOS/Tests/SettingsTests.swift (the new key)
```

**Structure Decision**: the model sits beside `LayerFit` in `Compositor` so both `ImageLayer` and `SceneFormat`
(which already depends on Compositor, not ImageLayer) use one type, and its tests run on Linux.

## Complexity Tracking

None.
