# Implementation Plan: VIS-016 Starfield Flight

**Branch**: `feature/vis-016` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/287-vis-016-starfield-flight/spec.md`

## Summary

A new native visual on the particle path (VIS-008/009): a seeded, fixed-pool star simulation on the injected
fixed-step clock, a CPU layout of perspective-scaled squares with a total-light bound, the FX-019 envelope, and the
reviewed flat-shape pass. Three new package files:

- `StarfieldConfiguration.swift`: `StarfieldSpeed` (slow/medium/fast), `StarfieldConfiguration` (density, speed,
  seed, Reduce Motion, palette, background; clamps), the constants and `activeCount`.
- `StarfieldSimulation.swift`: the 2000-star pool (allocated once), SplitMix64, `advance(toNanoseconds:)` in 1/240 s
  steps, `setBass(_:)`, `reset()`, respawn and skip counters.
- `StarfieldLayout.swift` (pure Swift) and `StarfieldGenerator.swift` (Metal): squares, the light bound, flash areas,
  tessellation, `FlatShapePass`.

The app adds Visual choice "Starfield", keys `settings.starfield.speed` and `settings.starfield.density`,
`StarfieldOptions` (picker and stepper), host style `.starfield(speed:density:)` in a new host extension file, with
minimal hooks in the shared files.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal, FlashSafety. No new package dependency.

**Storage**: Two UserDefaults keys.

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators --filter Starfield` (host and Linux
shape), RenderGoldens golden (macOS host, iOS Simulator), app unit tests and one UI test on "VIS16 iPhone 17".

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Performance Goals**: ≤ 2000 × 4 star updates and ≤ 12 000 vertices per 60 Hz frame; no allocation per frame; D1
frame rate `{device}`.

**Constraints**: owner rule 7 budgets (new host tests ≈ 3 s total); injected clocks only; type-check budget; no new
shader or compile site; VIS-012 edits the noise field in parallel, so nothing there is touched.

**Scale/Scope**: 4 new package sources; 3 package test files; 1 golden test; ~10 app files (2 new); 1 app test file;
1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator takes bands, a frame context and a configuration; it knows nothing of settings or projectM. |
| VII Real-time safety | Pool, squares, colours, flash areas and vertex buffers preallocated; nothing on an audio callback. |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, GPU, golden and UI tests; device look and frame rate stay `{device}`. |
| SHD-011 shader policy | No shader text added: `FlatShapePass.shaderSource` is reused as is. |

Post-design re-check: no violation; no ADR needed.

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualGenerators/
  StarfieldConfiguration.swift, StarfieldSimulation.swift, StarfieldLayout.swift   # NEW, pure Swift
  StarfieldGenerator.swift                                                          # NEW, Metal
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
  StarfieldSimulationTests.swift, StarfieldFlashTests.swift, StarfieldRenderTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/StarfieldGoldenTests.swift (+ GeneratorGoldens/Starfield)
Apps/projectM-iOS/... AppSettings, AppCoordinator, NativeSpectrumHost (+ NativeSpectrumHost+Starfield.swift),
  SettingsView, VisualizerView, SceneAutosaveCapture, ShowSceneSnapshot, SnapshotBatchJob;
  Views/StarfieldOptions.swift; Tests/StarfieldAppTests.swift (+ CameraVisualTests, SettingsTests);
  UITests/StarfieldUITests.swift; LibrarySettings.swift, run_device_tests.py
```

**Structure Decision**: Follow VIS-009 (own generator on the flat-shape pass), with VIS-015's app wiring.
