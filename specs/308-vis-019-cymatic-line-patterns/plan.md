# Implementation Plan: VIS-019 Cymatic Line Patterns

**Branch**: `feature/vis-019` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/308-vis-019-cymatic-line-patterns/spec.md`

## Summary

An eighth mode of the noise field generator (VIS-013's `NoiseFieldGenerator`, exactly as VIS-017): a square-plate
(Chladni) standing-wave field drawn as its nodal lines by a new entry point (`vis_cym_fragment`) in the generator's
module-constant shader. A pure-Swift CPU mirror (`CymaticField`) evaluates the same field, line intensity and colour, so
the nodal masks, finiteness and settle rule are testable on every platform and the FX-019 envelope is estimated from 64
mirrored samples. A drive (`CymaticDrive`) picks the target mode from the loudest band of the user-selected range
(with hysteresis), slews nine blend weights and the amplitude linearly on the injected frame clock, and settles exactly
to the resting mode in silence. A debug entry point (`vis_cym_mask_fragment`, tests only) writes each pixel's blended
field value and line intensity so the GPU nodal mask is measured directly.

The app adds Visual choice "Cymatic Lines", key `settings.cymatic.bands`, `CymaticOptions` (segmented picker), host
style `.cymatic(bands:)`, with one-line additive hooks in the shared files (VIS-018 edits the same files in parallel).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode; Metal Shading Language
(runtime-compiled module constant).

**Primary Dependencies**: Metal, FlashSafety. Tests also use AnalysisFeatures/AudioCore (pure tones through the real
ANL-002 reducer via `SpectrumBandFeed`). No new package dependency.

**Storage**: One UserDefaults key.

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators --filter Cymatic` (host, and the Linux shape
with `-Xswiftc -DVISUAL_NO_METAL`), RenderGoldens golden (macOS host, iOS Simulator), app unit tests and one UI test on
the agent's own "VIS19 iPhone 17" simulator.

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Performance Goals**: ≤ 9 modes × 4 cosines per pixel (modes at weight 0 skipped; settled = 1 mode); CPU mirror 64
samples per frame; drive O(bands) per frame; no allocation per frame; D1 frame rate `{device}`.

**Constraints**: owner rule 7 budgets; injected clocks only; type-check budget; no new compile site (SHD-011);
VIS-018 edits the same shared files in parallel, so shared-file edits are one line and additive (separate `case` lines,
not edits of existing lines, where possible).

**Scale/Scope**: 2 new package sources and small edits in 3 (configuration, generator, flash areas); 3 package test
files; 1 golden test; ~10 app files (3 new); 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator takes bands, a frame context and a configuration; it knows nothing of settings or projectM. |
| VII Real-time safety | Uniforms, weights and samples preallocated (SIMD values); nothing on an audio callback. |
| VIII Upstream fidelity | Nothing reaches projectM; no FFT or beat analysis duplicated (bands come from ANL-002). |
| IX Dependencies | None added. |
| X Evidence | Unit, GPU, golden and UI tests; device look and frame rate stay `{device}`. |
| SHD-011 shader policy | Module-authored text added to an already reviewed compile site (`NoiseFieldGenerator.swift`, ADR-0066); no user text, no new site. |

Post-design re-check: no violation; no ADR needed.

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualGenerators/
  CymaticPattern.swift   # NEW, pure Swift: band range, settings, mode table, field, line, shade (CPU mirror), MSL text
  CymaticDrive.swift     # NEW, pure Swift: band selection, hysteresis, weight and amplitude slews, settle
  NoiseFieldConfiguration.swift, NoiseFieldGenerator.swift, NoiseFieldFlashAreas.swift   # small additive edits
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
  CymaticPatternTests.swift, CymaticFlashTests.swift, CymaticRenderTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/CymaticGoldenTests.swift (+ GeneratorGoldens/Cymatic)
Apps/projectM-iOS/... AppSettings, AppCoordinator, NativeSpectrumHost, SettingsView, VisualizerView,
  SceneAutosaveCapture, ShowSceneSnapshot, SnapshotBatchJob; Views/CymaticOptions.swift;
  Visuals/CymaticHostSupport.swift; Tests/CymaticAppTests.swift (+ CameraVisualTests, SettingsTests);
  UITests/CymaticUITests.swift; LibrarySettings.swift, run_device_tests.py
```

**Structure Decision**: Follow VIS-017 (a noise field mode with its own entry point, host-support file, options view,
one-modifier `VisualizerView` chain).
