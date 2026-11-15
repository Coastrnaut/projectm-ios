# Implementation Plan: VIS-011 Fluid Ink

**Branch**: `feature/vis-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/280-vis-011-fluid-ink/spec.md`

## Summary

A stable-fluids ink visual driven by ANL-004 onsets, as a fifth mode of the VIS-013 noise field generator. New package
files in `VisualGenerators`:

- `FluidInk.swift` (pure Swift, every platform): constants (`FluidInk`), the impulse model (`FluidImpulse`, strength
  mapping, seeded splats), the fixed-step clock and impulse queue (`FluidStepScheduler`: anchor, 1/60 s steps, ≤ 4 per
  frame, stall skip, 16-entry queue, ≤ 2 impulses / 1.5 strength per step, Reduce Motion spacing), the global ink
  bound for the envelope (`FluidInkBound`) and the health record (`FluidInkHealth`). The reference solver
  (`FluidInkSolver`, any grid size, fixed storage, same passes and arithmetic as the shaders, non-finite guard, health
  statistics) is in its own target `VisualFluidReference` (tests only; compiled with `-O` so Debug runs stay short).
- `FluidInkPass.swift` (Metal): the fixed textures (made once), the pass pipelines built from the noise field
  generator's library through PERF-009's archive, per-step encoding, the display pass, and the health image with its
  non-blocking readback.
- `FluidInkShader.functions` (MSL text) appended to `NoiseFieldGenerator.shaderSource` (reviewed site, ADR-0066).

Small hooks: `NoiseFieldConfiguration.fluidInk` (forces the other modes off), mode `.fluid` in `NoiseFieldGenerator`
(lazy pass, `enqueueImpulse`, restart/mode-entry reset), `NoiseFieldFlashAreas.loadUniform` for the bound.

App: `VisualChoice.fluidInk`, `NativeSpectrumStyle.fluidInk`, the host drains its analysis subscription into the
generator (as the fountain), accessibility value, scene capture as no layer, settings description text.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal, FlashSafety, AnalysisFeatures (app side only); no new dependency.

**Storage**: none new (no UserDefaults key; `settings.visual` gains the value `fluidInk`).

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators --filter FluidInk` (host, about 5 s total;
Linux shape `-Xswiftc -DVISUAL_NO_METAL`), RenderGoldens golden (macOS host, iOS Simulator), app unit tests and one
UI test on "VIS11 iPhone 17". Long sweeps behind `VIS011_LONG=1`.

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the CPU parts.

**Performance Goals**: per step 6 + 20 full-grid passes on 128² (about 0.4 M fragment invocations), at most 4 steps
per frame; one display pass at output size; D1 frame rate `{device}`.

**Constraints**: owner rule 7 budgets; VisualGenerators suite already over budget, so new host tests ≲ 5 s; type-check
budget; existing goldens unchanged; no new compile site.

**Scale/Scope**: 2 new package source files, 3 edited package files; ~6 app files; 3 package test files, 1 golden test,
1 app test file, 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The solver lives in `VisualGenerators`; the app only selects the visual and forwards onsets. |
| VII Real-time safety | Textures and buffers made once; uniforms by `setFragmentBytes` from stack values; readback without waiting; nothing on an audio callback. |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, GPU, golden and UI tests; device look and frame rate stay `{device}`. |
| SHD-011 shader policy | Fluid MSL is a module constant appended to the reviewed `NoiseFieldGenerator.shaderSource` (already a PERF-009 archive key source); no compute, no new compile site. |

Post-design re-check: no violation; no ADR needed.

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualGenerators/
  FluidInk.swift                  # NEW: constants, impulses, scheduler, bound, health
Packages/VisualGenerators/Sources/VisualFluidReference/
  FluidInkSolver.swift            # NEW target (tests only, -O): the CPU reference solver
  FluidInkPass.swift              # NEW: textures, pipelines, step/display encoding, health readback; FluidInkShader
  NoiseFieldConfiguration.swift   # + fluidInk
  NoiseFieldGenerator.swift       # + mode .fluid, shader source, enqueueImpulse
  NoiseFieldFlashAreas.swift      # + loadUniform(bound)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
  FluidInkSolverTests.swift, FluidInkRenderTests.swift, FluidInkFlashTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/FluidInkGoldenTests.swift (+ GeneratorGoldens/FluidInk)
Apps/projectM-iOS/ AppSettings, AppCoordinator, SnapshotBatchJob, SceneAutosaveCapture, ShowSceneSnapshot,
  NativeSpectrumHost, SettingsView; Tests/FluidInkAppTests.swift; UITests/FluidInkUITests.swift
```

**Structure Decision**: the fluid is a self-contained pass owned by the noise field generator, so the generator file
changes by a mode and a delegation branch.
