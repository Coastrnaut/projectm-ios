# Implementation Plan: VIS-012 Reaction Diffusion

**Branch**: `feature/vis-012` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/286-vis-012-reaction-diffusion/spec.md`

## Summary

A Gray–Scott reaction-diffusion visual with stored seed patterns and a bounded iteration count, as a sixth mode of the
VIS-013 noise field generator, built on VIS-011's template. New package files in `VisualGenerators`:

- `ReactionDiffusion.swift` (pure Swift, every platform): constants (`ReactionDiffusion`), presets and clamped
  parameters (`ReactionDiffusionPreset`, `GrayScottParameters`), seed patterns (`ReactionDiffusionPattern`), the stored
  settings (`ReactionDiffusionSettings`), the seed texture generator (`ReactionDiffusionSeed.fill`), the bass kick
  detector and the fixed-step scheduler with injections (`ReactionDiffusionScheduler`), the light bound
  (`ReactionDiffusionBound`) and the health record (`ReactionDiffusionHealth`).
- `ReactionDiffusionPass.swift` (Metal): the fixed textures and the seed staging buffer (made once), pipelines from the
  generator's library through PERF-009's archive, seeding by blit, iteration encoding, the health image with its
  non-blocking readback, the display; `ReactionDiffusionShader.functions` (MSL) appended to
  `NoiseFieldGenerator.shaderSource`.
- `VisualFluidReference/GrayScottSolver.swift`: the CPU reference (tests only, `-O`).

Small hooks: `NoiseFieldConfiguration.reactionDiffusion` (optional settings; forces the other modes off), mode
`.reaction` in `NoiseFieldGenerator` (lazy pass, reload on entry / settings change / restart / health failure).

App: `VisualChoice.reactionDiffusion`, four `AppSettings` keys, `NativeSpectrumStyle.reactionDiffusion(_)`,
`ReactionDiffusionOptions` view, accessibility value, scene capture as no layer, key lists (FILE-005, device tests).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal, FlashSafety; no new dependency.

**Storage**: four UserDefaults keys `settings.reactionDiffusion.{preset,pattern,seed,speed}` (FR-065: settings only).

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators --filter ReactionDiffusion` (host, ≈ 5 s;
Linux shape `-Xswiftc -DVISUAL_NO_METAL`), a RenderGoldens golden (macOS host, iOS Simulator), app unit tests and one
UI test on "VIS12 iPhone 17". Long CPU sweeps behind `VIS012_LONG=1`.

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the CPU parts.

**Performance Goals**: at most 64 iterations of one 128² pass per frame (≈ 1 M fragment invocations in the worst
case; 8 per frame at the default Speed 8 and 60 fps); one display pass; D1 frame rate `{device}`.

**Constraints**: owner rule 7; VisualGenerators suite near its budget, so new host tests ≈ 5 s; type-check budget;
existing goldens unchanged; no new compile site.

**Scale/Scope**: 2 new package source files + 1 reference file, 3 edited package files; ~8 app files; 3 package test
files, 1 golden test, 1 app test file, 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, SwiftUI only. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The model lives in `VisualGenerators`; the app stores settings and selects the style. |
| VII Real-time safety | Textures and buffers made once; uniforms by `setFragmentBytes` from storage made in `init`; seeding writes the staging buffer in place; readback without waiting; nothing on an audio callback. |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, GPU, golden and UI tests; device look and frame rate stay `{device}`. |
| SHD-011 shader policy | MSL is a module constant appended to the reviewed `NoiseFieldGenerator.shaderSource`; no compute, no new compile site. |

Post-design re-check: no violation; no ADR needed.

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualGenerators/
  ReactionDiffusion.swift          # NEW: constants, presets, patterns, settings, seed, scheduler, bound, health
  ReactionDiffusionPass.swift      # NEW: textures, pipelines, seeding, iterations, health, display; shader text
  NoiseFieldConfiguration.swift    # + reactionDiffusion
  NoiseFieldGenerator.swift        # + mode .reaction, shader source
Packages/VisualGenerators/Sources/VisualFluidReference/GrayScottSolver.swift   # NEW (tests only)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
  ReactionDiffusionModelTests.swift, ReactionDiffusionRenderTests.swift, ReactionDiffusionFlashTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/ReactionDiffusionGoldenTests.swift (+ GeneratorGoldens/ReactionDiffusion)
Apps/projectM-iOS/ AppSettings, AppCoordinator, SnapshotBatchJob, SceneAutosaveCapture, ShowSceneSnapshot,
  NativeSpectrumHost, SettingsView, VisualizerView, Views/ReactionDiffusionOptions.swift;
  Tests/ReactionDiffusionAppTests.swift; UITests/ReactionDiffusionUITests.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py (keys)
```

**Structure Decision**: the reaction is a self-contained pass owned by the noise field generator, as VIS-011's fluid.
