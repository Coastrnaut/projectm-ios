# Implementation Plan: VIS-018 Geometric Tessellation

**Branch**: `feature/vis-018` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/307-vis-018-geometric-tessellation/spec.md`

## Summary

An eighth mode of the noise field generator (VIS-013's `NoiseFieldGenerator`, like VIS-012, VIS-015 and VIS-017): five
periodic tilings drawn per pixel by a new entry point (`vis_tess_fragment`) in the generator's module-constant shader.
A pure-Swift lattice (`TessellationLattice`) is the single definition of the tiling: it places the lattice from the
output size and tile count (tile size = shorter side / N, frame centre at a fixed symmetry point), classifies a point
into a tile (integer lattice coordinates + shape index), gives the tile's centre, its distance to the tile's edge and
its polygon. The shader text repeats the same arithmetic; a test-only entry point (`vis_tess_cells_fragment`) writes
each pixel's tile coordinates and edge distance so the GPU is checked against the CPU at every pixel. A drive
(`TessellationDrive`) turns VIS-007's band groups into the seam inset, colour drift, travelling-light phase and
brightness on the injected frame clock. Symmetry shapes the colouring only, so the lattice (and its alignment) never
depends on symmetry, time or audio.

The app adds Visual choice "Tessellation", five keys, `TessellationOptions`, host style `.tessellation(...)`, with
one-line hooks in the shared files and a host-support file (`TessellationHostSupport.swift`).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode; Metal Shading Language
(runtime-compiled module constant).

**Primary Dependencies**: Metal, FlashSafety. No new package dependency.

**Storage**: Five UserDefaults keys.

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators --filter Tessellation` (host, and the Linux
shape with `-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`), RenderGoldens golden (macOS host, iOS
Simulator), app unit tests and one UI test on the agent's own "VIS18 iPhone 17" simulator (iOS 27.2).

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Performance Goals**: per pixel one tile classification (≤ 4 candidate distances) and a palette lookup; CPU mirror 64
classifications per frame; no allocation per frame; D1 frame rate `{device}`.

**Constraints**: owner rule 7 budgets (unit ≤ 10 s, suite < 1 min, UI < 30 s); injected clocks only; type-check budget;
no new compile site (SHD-011); FX-015/FX-016 edit Compositor, SettingsView, AppCoordinator and key lists in parallel,
so shared-file edits are small and additive.

**Scale/Scope**: 3 new package sources (lattice + shader text, drive + settings, nothing else) and small edits in 3
(configuration, generator, flash areas); 4 package test files; 1 golden test; ~12 app files (4 new); 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator takes bands, a frame context and a configuration; it knows nothing of settings or projectM. |
| VII Real-time safety | Uniforms and samples preallocated; nothing on an audio callback; per-pixel work bounded (no loops over tiles). |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | CPU alignment sweep, GPU-vs-CPU per-pixel check, golden and UI tests; device look and frame rate stay `{device}`. |
| SHD-011 shader policy | Module-authored text added to an already reviewed compile site (`NoiseFieldGenerator.swift`, ADR-0066); no user text, no new site. |

Post-design re-check: no violation; no ADR needed (no default overridden).

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualGenerators/
  TessellationLattice.swift   # NEW, pure Swift: tilings, settings, placement, classify, polygon, colouring; MSL text
  TessellationDrive.swift     # NEW, pure Swift: band-driven inset, drift, light phase, brightness
  NoiseFieldConfiguration.swift, NoiseFieldGenerator.swift, NoiseFieldFlashAreas.swift   # small additive edits
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
  TessellationAlignmentTests.swift, TessellationDriveTests.swift, TessellationFlashTests.swift, TessellationRenderTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/TessellationGoldenTests.swift (+ GeneratorGoldens/Tessellation)
Apps/projectM-iOS/... AppSettings, AppCoordinator, NativeSpectrumHost, SettingsView, VisualizerView,
  SceneAutosaveCapture, ShowSceneSnapshot, SnapshotBatchJob; Views/TessellationOptions.swift;
  Visuals/TessellationHostSupport.swift; Tests/TessellationAppTests.swift (+ CameraVisualTests, SettingsTests);
  UITests/TessellationUITests.swift; LibrarySettings.swift, run_device_tests.py
```

**Structure Decision**: Follow VIS-017 (a noise field mode with its own entry point and a CPU mirror) for the package
and its host-support file for the app.

## Complexity Tracking

None.
