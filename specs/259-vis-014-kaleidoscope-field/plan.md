# Implementation Plan: VIS-014 Kaleidoscope Field

**Branch**: `feature/vis-014` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/259-vis-014-kaleidoscope-field/spec.md`

## Summary

An eleventh native visual: VIS-013's seeded noise field, folded into N mirrored wedges about the frame centre
and turned by the bass. The fold is one shared module in `VisualGenerators`, `KaleidoscopeFold` (CPU mirror:
`fold(_:)`, plus the turning drive constants) and `KaleidoscopeFoldShader.function` (MSL text of `vis_kfold`). The
noise field's existing reviewed generator gains the fold: `NoiseFieldConfiguration.wedges` (0 = no fold, else
2…24), two uniforms in the block's former padding (wedges, rotation; the layout keeps its size) and a second
fragment entry point `vis_kaleido_fragment` beside the untouched `vis_noise_fragment` (both call one shared shading
helper), each with its own pipeline (the initial mode's built in `init`, the other on first use); the plain field's
frames stay byte-identical (its digests and goldens match exactly; a branch inside one entry point changed 1-3
golden pixels by 1/255, so it was rejected). `NoiseFieldDrive`
gains the smoothed bass spin and the rotation angle (advanced only when folded). `NoiseFieldFlashAreas` folds its
64 sample points the same way. The app adds the Visual choice "Kaleidoscope" with one key
(`settings.kaleidoscope.wedges`) and a Wedges stepper. Proof: GPU N-fold rotation and mirror symmetry tests that
follow N, a seam test across every boundary and axis, CPU fold continuity and CPU/GPU agreement, drive and flash
tests, one golden per platform class, app tests and a short UI test.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal, FlashSafety (envelope). No new package dependency.

**Storage**: One UserDefaults key (`settings.kaleidoscope.wedges`).

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators` (host and Linux shape
`-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`), `Packages/RenderGoldens` golden (macOS host, iOS
Simulator), app unit tests and one UI test on "VIS14 iPhone 17".

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Project Type**: iOS app with SwiftPM packages.

**Performance Goals**: the noise field's pass plus one `atan2`, `floor` and `sincos` per pixel; 64 folded CPU
samples per frame; no allocation per frame; frame rate on D1 is `{device}`.

**Constraints**: owner rule 7 test budgets; no wall-clock assertions; type-check budget; the noise field's digests
unchanged; no new Metal compile site (ADR-0024 / ADR-0066).

**Scale/Scope**: 1 new package source file; 4 edited package files; about 10 app files; 3 package test files,
1 golden test, 1 app unit test file, 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator receives bands, a frame context and a configuration; it knows nothing of analysis, settings or projectM. |
| VII Real-time safety | Uniforms, samples and envelope storage preallocated; nothing on an audio callback. |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, GPU, golden and UI tests; device frame rate stays `{device}`. |
| SHD-011 shader policy | The fold text is a module constant appended to the already-reviewed `NoiseFieldGenerator.shaderSource`; no new compile site, nothing from user text. |

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualGenerators/
  KaleidoscopeFold.swift          # NEW: CPU fold + MSL text + turning constants
  NoiseFieldConfiguration.swift   # + wedges (0 or 2…24), kaleidoscope(wedges:) preset
  NoiseFieldDrive.swift           # + spin (smoothed low) and rotation (folded only)
  NoiseFieldFlashAreas.swift      # folds the sample points
  NoiseFieldGenerator.swift       # fold function, two uniforms in the old padding
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
  KaleidoscopeFoldTests.swift, KaleidoscopeRenderTests.swift, KaleidoscopeDriveFlashTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/KaleidoscopeGoldenTests.swift (+ GeneratorGoldens/Kaleidoscope)
Apps/projectM-iOS/... AppSettings, AppCoordinator, NativeSpectrumHost, SettingsView, VisualizerView,
  SceneAutosaveCapture, ShowSceneSnapshot, SnapshotBatchJob; Views/KaleidoscopeOptions.swift;
  Tests/KaleidoscopeAppTests.swift; UITests/KaleidoscopeUITests.swift
```

**Structure Decision**: Follow VIS-013 exactly and extend its generator instead of adding a second one.
