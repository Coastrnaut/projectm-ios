# Tasks: VIS-011 Fluid Ink

**Input**: `specs/280-vis-011-fluid-ink/` (spec, plan, research, data-model, contracts/fluid-ink.md, quickstart)

Tests are requested by the spec (stability acceptance, frame-rate equality, allocation, goldens, flash, UI). `{device}`
marks work the Mac cannot finish.

## Phase 1: Setup

- [ ] VIS-011-T01 Create simulator "VIS11 iPhone 17" (iOS 27.2), init preset submodules, `xcodegen generate` in the worktree

## Phase 2: Foundational (CPU model, every platform)

- [ ] VIS-011-T02 `FluidInk` constants ("grid 128, step 1/60 s, maxStepsPerFrame 4, jacobi 20, speedCap 0.45 (× 0.5 Reduce Motion), velocityHalfLife 1 s, inkHalfLife 2.5 s, inkCap 0.8"), `FluidImpulse.strength(onset:threshold:)` (0.4…1, non-finite → nil), seeded `FluidSplat`, `FluidStepScheduler` (anchor, ≤ 4 steps, stall skip, queue 16, ≤ 2 impulses and ≤ 1.5 strength per step, Reduce Motion spacing 0.5 s), `FluidInkBound`, `FluidInkSolver` (reference, any N, fixed storage, non-finite reset, health) in Packages/VisualGenerators/Sources/VisualGenerators/FluidInk.swift
- [ ] VIS-011-T03 [P] Solver tests: 60 s of max impulses every frame at 32² (finite, speed ≤ cap, ink ≤ 0.8, kinetic energy bounded and not growing); 30 vs 120 fps bit-identical at shared times; scheduler caps and stall skip; impulse mapping; non-finite reset; bound ≥ solver max ink; storage fixed in Packages/VisualGenerators/Tests/VisualGeneratorsTests/FluidInkSolverTests.swift

## Phase 3: US1 + US2 Ink on the GPU, stable (P1)

- [ ] VIS-011-T04 [US1] `FluidInkShader.functions` (splat, advect velocity, divergence, Jacobi, gradient, advect ink, health, display; manual bilinear; non-finite → 0) appended to `NoiseFieldGenerator.shaderSource`; `FluidInkPass` (fixed textures made once, pipelines via `NativePipelineArchive`, step and display encoding, health readback without waiting) in Packages/VisualGenerators/Sources/VisualGenerators/FluidInkPass.swift
- [ ] VIS-011-T05 [US1] `NoiseFieldConfiguration.fluidInk` (forces the other modes off) and `fluidInk(reduceMotion:palette:)`; mode `.fluid` in `NoiseFieldGenerator` (lazy pass, `enqueueImpulse`, reset on mode entry and `restartLoop`, gain from the bound) in NoiseFieldConfiguration.swift, NoiseFieldGenerator.swift, NoiseFieldFlashAreas.swift
- [ ] VIS-011-T06 [US2] GPU tests: 60 s of max impulses (health readback finite and within caps, kinetic energy bounded); GPU matches the reference solver at 32²; 30 vs 120 fps identical readback; texture count, identity and `allocatedSize` constant over resizes and mode switches; existing modes unchanged in Packages/VisualGenerators/Tests/VisualGeneratorsTests/FluidInkRenderTests.swift
- [ ] VIS-011-T07 [US1] Golden of a scripted impulse timeline, macOS host and iOS Simulator, in Packages/RenderGoldens/Tests/RenderGoldensTests/FluidInkGoldenTests.swift (+ GeneratorGoldens/FluidInk)

## Phase 4: US3 Safe light and Reduce Motion (P1)

- [ ] VIS-011-T08 [US3] Flash tests: the bound bounds the drawn ink's light (GPU readback), the envelope's gain scales the drawn picture, Reduce flashing budget holds with bursts after silence, Reduce Motion halves speed and spaces impulses in Packages/VisualGenerators/Tests/VisualGeneratorsTests/FluidInkFlashTests.swift

## Phase 5: US4 Choose it (P2)

- [ ] VIS-011-T09 [US4] `VisualChoice.fluidInk` ("Fluid Ink", native, no Bars), host style `.fluidInk` (in place with noise-field modes, drains onsets into `enqueueImpulse`, accessibility value "Ink from sudden sounds, Glow …"), coordinator and snapshot mapping, scene capture as no layer, Settings description in Apps/projectM-iOS/Coordinators/AppSettings.swift, AppCoordinator.swift, SnapshotBatchJob.swift, SceneAutosaveCapture.swift, ShowSceneSnapshot.swift, Visuals/NativeSpectrumHost.swift, Views/SettingsView.swift
- [ ] VIS-011-T10 [P] [US4] App tests (choice persists, host builds the fluid mode, onsets reach the generator, in-place switches, accessibility value, no scene layer) in Apps/projectM-iOS/Tests/FluidInkAppTests.swift; SettingsTests, LibraryBackupAppTests, CameraVisualTests pass
- [ ] VIS-011-T11 [P] [US4] UI test (≤ 30 s): choose Fluid Ink, value names it, Bars hidden in Apps/projectM-iOS/UITests/FluidInkUITests.swift

## Phase 6: Polish

- [ ] VIS-011-T12 Repo checks, Linux shape build, type-check budget, privacy manifest and network symbols, PosterBoard counts, docs match the implementation
- [ ] VIS-011-T13 {device} D1: Fluid Ink with music; ink follows onsets, frame rate holds on the PERF-001/007 overlay, no flashing with Reduce flashing on

## Dependencies

T02 → T03, T04 → T05 → T06, T07, T08 → T09 → T10, T11; T12 last. T13 needs a device.

## Parallel examples

T03 alongside T04; T07 and T08 after T05; T10 and T11 after T09.

## Implementation strategy

MVP = T02-T06 (the acceptance: stability on the reference solver and the GPU). Then golden and safety, then the app.

## Analyze notes (speckit-analyze, 2026-11-14)

- Coverage: R1, R9 T04-T05; R2, R5, R6 T02-T03, T05; R3, R4, R7 T02-T06; R8 T06; R10, R11 T08; R12 T09-T11; R13 T07.
  S1-S6 each have a test task. No constitution conflict (no new compile site, no compute, no networking, nothing reaches
  projectM).
- Fix applied (ambiguity): "kinetic energy not growing" is now measurable in US2 scenario 1 and S1 (absolute bound
  ½ × cells × cap², last-10 s mean ≤ 1.25 × previous 10 s).
- Fix applied (inconsistency): the GPU health check's 1 % over-cap tolerance (research D5) is now in the spec.
