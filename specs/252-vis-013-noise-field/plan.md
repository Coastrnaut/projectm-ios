# Implementation Plan: VIS-013 Noise Field

**Branch**: `feature/vis-013` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/252-vis-013-noise-field/spec.md`

## Summary

A tenth native visual beside VIS-001 to VIS-009: a full-screen field of layered, seeded, domain-warped value
noise coloured by the palette, drifting on the frame clock and swirling and brightening with ANL-002's bands.
SHD-006's lattice hash, value noise and fBm move into `VisualGenerators` as `SeededNoise` (CPU mirror) and
`SeededNoiseShader.functions` (GPU function text); the material's `NoiseTextureReference` calls the CPU mirror,
and a ProceduralMaterials test pins that the material's literal contains the shared text verbatim.
`NoiseFieldConfiguration` (frequency, octaves, seed, Reduce Motion, palette) and `NoiseFieldDrive` (pure Swift:
band groups → smoothed warp and brightness, drift phase on the injected clock) build everywhere;
`NoiseFieldFlashAreas` samples the CPU mirror on an 8 × 8 grid for FX-019's 17 areas; `NoiseFieldGenerator`
(Metal) draws one full-screen triangle with a fragment shader built from the shared text plus its own body.
The app adds the Visual choice "Noise Field" with three keys (frequency, octaves, seed) and a New Seed button
(SHD-006's `NoiseSeedSequence`). Proof: GPU determinism with per-GPU digests, seed sensitivity, CPU/GPU
agreement, drive acceptance, flash-envelope tests, one golden per platform class, app tests and a short UI test.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal, FlashSafety (envelope). No new package dependency (ProceduralMaterials already
depends on VisualGenerators).

**Storage**: Three UserDefaults keys (`settings.noiseField.frequency`, `.octaves`, `.seed`).

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators` (host and Linux shape
`-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`), `Packages/Compositor` ProceduralMaterialsTests
(digests unchanged), `Packages/RenderGoldens` golden (macOS host, iOS Simulator), app unit tests and one UI test
on "VIS13 iPhone 17".

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Project Type**: iOS app with SwiftPM packages.

**Performance Goals**: one full-screen fragment pass (≤ 6 octaves × 3 fields of 4 hashes per pixel), 64 CPU
samples per frame for the flash estimate, no allocation per frame; frame rate on D1 is `{device}`.

**Constraints**: owner rule 7 test budgets; no wall-clock assertions; type-check budget; the material's shader
literal and source-safety test unchanged.

**Scale/Scope**: 5 new package source files; one edited CPU reference; edits to about 10 app files; 4 package
test files, 1 material test, 1 golden test, 1 app unit test file, 1 UI test.

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
| SHD-011 shader policy | Shader source is module-authored constants only; nothing compiled from user text, files or downloads. |

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualGenerators/
  SeededNoise.swift               # CPU mirror + GPU function text (moved from SHD-006)
  NoiseFieldConfiguration.swift   # settings, ranges, constants
  NoiseFieldDrive.swift           # band groups → warp, brightness; drift phase
  NoiseFieldFlashAreas.swift      # 8 × 8 CPU samples → 17 areas
  NoiseFieldGenerator.swift       # Metal (compiled out on Linux)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
  NoiseFieldDriveTests.swift, NoiseFieldFlashTests.swift, NoiseFieldRenderTests.swift, SeededNoiseTests.swift
Packages/Compositor/Sources/ProceduralMaterials/NoiseTextureReference.swift   # calls SeededNoise
Packages/Compositor/Tests/ProceduralMaterialsTests/SharedNoiseSourceTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/NoiseFieldGoldenTests.swift (+ GeneratorGoldens/NoiseField)
Apps/projectM-iOS/... AppSettings, AppCoordinator, NativeSpectrumHost, SettingsView, VisualizerView,
  SceneAutosaveCapture, ShowSceneSnapshot, SnapshotBatchJob, OfflineSceneRenderer; Tests/NoiseFieldAppTests.swift;
  UITests/NoiseFieldUITests.swift
```

**Structure Decision**: Follow VIS-007 to VIS-009 exactly; the only new pattern is the fragment-shader pass,
which lives inside the generator (one pipeline through `NativePipelineArchive`).
