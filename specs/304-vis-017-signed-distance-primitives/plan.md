# Implementation Plan: VIS-017 Signed-Distance Primitives

**Branch**: `feature/vis-017` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/304-vis-017-signed-distance-primitives/spec.md`

## Summary

A seventh mode of the noise field generator (VIS-013's `NoiseFieldGenerator`, like VIS-012 and VIS-015): a bounded
sphere-traced scene of one sphere, one torus and four boxes, marched per pixel by a new entry point
(`vis_sdf_fragment`) in the generator's module-constant shader, with a per-preset step cap, a bounding-sphere entry and
exit, a hit threshold and NaN guards. A pure-Swift CPU mirror (`SignedDistanceScene`) evaluates the same distance field
and march, so the step caps and finiteness are testable on every platform and the FX-019 envelope is estimated from
64 mirrored samples. A drive (`SignedDistanceDrive`) turns VIS-007's band groups into swell, turning angle and
brightness on the injected frame clock. A debug entry point (`vis_sdf_steps_fragment`, tests only) writes each
pixel's step count so the GPU cap is measured directly.

The app adds Visual choice "SDF Shapes", key `settings.signedDistance.quality`, `SignedDistanceOptions` (segmented
picker), host style `.signedDistance(quality:)`, with one-line hooks in the shared files.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode; Metal Shading Language
(runtime-compiled module constant).

**Primary Dependencies**: Metal, FlashSafety. No new package dependency.

**Storage**: One UserDefaults key.

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators --filter SignedDistance` (host, and the Linux
shape with `-Xswiftc -DVISUAL_NO_METAL`), RenderGoldens golden (macOS host, iOS Simulator), app unit tests and one UI
test on the agent's own "VIS17 iPhone 17" simulator.

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Performance Goals**: ≤ cap + 4 scene evaluations (6 primitives each) per pixel; Medium = 48 steps; CPU mirror ≤ 64 ×
(96 + 4) evaluations per frame; no allocation per frame; D1 frame rate `{device}`.

**Constraints**: owner rule 7 budgets; injected clocks only; type-check budget; no new compile site (SHD-011);
FX-014/FX-015 edit the effect chain, settings key lists and `VisualizerView.swift` in parallel, so shared-file edits are
small and additive.

**Scale/Scope**: 3 new package sources and small edits in 3 (configuration, generator, flash areas); 3 package test
files; 1 golden test; ~10 app files (3 new); 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator takes bands, a frame context and a configuration; it knows nothing of settings or projectM. |
| VII Real-time safety | Uniforms and samples preallocated; nothing on an audio callback; the march is bounded. |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, GPU, golden and UI tests; device look and frame rate stay `{device}`. |
| SHD-011 shader policy | Module-authored text added to an already reviewed compile site (`NoiseFieldGenerator.swift`, ADR-0066); no user text, no new site. |

Post-design re-check: no violation; no ADR needed.

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualGenerators/
  SignedDistanceScene.swift   # NEW, pure Swift: quality, settings, distance field, march, CPU mirror, MSL text
  SignedDistanceDrive.swift   # NEW, pure Swift: band-driven swell, angle, brightness
  NoiseFieldConfiguration.swift, NoiseFieldGenerator.swift, NoiseFieldFlashAreas.swift   # small additive edits
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
  SignedDistanceSceneTests.swift, SignedDistanceFlashTests.swift, SignedDistanceRenderTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/SignedDistanceGoldenTests.swift (+ GeneratorGoldens/SignedDistance)
Apps/projectM-iOS/... AppSettings, AppCoordinator, NativeSpectrumHost, SettingsView, VisualizerView,
  SceneAutosaveCapture, ShowSceneSnapshot, SnapshotBatchJob; Views/SignedDistanceOptions.swift;
  Visuals/SignedDistanceHostSupport.swift; Tests/SignedDistanceAppTests.swift (+ CameraVisualTests, SettingsTests);
  UITests/SignedDistanceUITests.swift; LibrarySettings.swift, run_device_tests.py
```

**Structure Decision**: Follow VIS-012 (a noise field mode with its own entry point) for the package and VIS-016's
host-support file for the app.
