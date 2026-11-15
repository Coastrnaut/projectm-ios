# Tasks: VIS-012 Reaction Diffusion

**Input**: `specs/286-vis-012-reaction-diffusion/` (spec, plan, research, data-model, contracts/reaction-diffusion.md, quickstart)

Tests are requested by the spec (determinism, never-NaN, iteration bound, allocation, goldens, flash, app, UI).
`{device}` marks work the Mac cannot finish.

## Phase 1: Setup

- [ ] VIS-012-T01 Create simulator "VIS12 iPhone 17" (iOS 27.2), check presets and `Build`, `xcodegen generate` in the worktree

## Phase 2: Foundational (CPU model, every platform)

- [ ] VIS-012-T02 `ReactionDiffusion` constants ("grid 128, step 1/60 s, maximumStepsPerFrame 4, speed 1…16 default 8, maximumIterationsPerFrame 64, fade-in 1 s, injection radius 0.04 amount 0.25, queue 4, kick above 0.6 after below 0.4, spacing 0.25 s / 1 s Reduce Motion"), `ReactionDiffusionPreset` (coral|mitosis|spots|maze), `GrayScottParameters` (clamped "F 0.01…0.10, k 0.04…0.07, Du 0.2…1.0, Dv 0.1…0.5"), `ReactionDiffusionPattern` (square|spots|ring|stripes), `ReactionDiffusionSettings` ("seed 0…9999 default 1, speed 1…16 default 8"; out of range → default), `ReactionDiffusionSeed.fill`, `ReactionDiffusionScheduler` (anchor, ≤ 4 steps, stall skip, kick detector, ≤ 1 injection per step, seeded injections), `ReactionDiffusionBound`, `ReactionDiffusionHealth` in Packages/VisualGenerators/Sources/VisualGenerators/ReactionDiffusion.swift; `GrayScottSolver` in Packages/VisualGenerators/Sources/VisualFluidReference/GrayScottSolver.swift
- [ ] VIS-012-T03 [P] Model tests: seed determinism (same settings → identical texture; other seed differs; settings round-trip), iteration bound at 10/30/60/120 fps (≤ 4 steps, ≤ 64 iterations), kick detector and injection caps, Reduce Motion halves iterations, CPU reference finite and in [0, 1] for every preset at Speed 16 with injections (long run behind `VIS012_LONG=1`) in Packages/VisualGenerators/Tests/VisualGeneratorsTests/ReactionDiffusionModelTests.swift

## Phase 3: US1 + US2 Pattern on the GPU, reproducible, never NaN (P1)

- [ ] VIS-012-T04 [US1] `ReactionDiffusionShader.functions` (iterate with injection, health, display; exponent-bit guard) appended to `NoiseFieldGenerator.shaderSource`; `ReactionDiffusionPass` (state pair + health made once, staging buffer, seeding blit, iterations, health readback, display) in Packages/VisualGenerators/Sources/VisualGenerators/ReactionDiffusionPass.swift
- [ ] VIS-012-T05 [US1] `NoiseFieldConfiguration.reactionDiffusion` (forces the other modes off) and mode `.reaction` in `NoiseFieldGenerator` (lazy pass, reload on entry, preset/pattern/seed change, restart and health flag; gain from the bound) in NoiseFieldConfiguration.swift, NoiseFieldGenerator.swift
- [ ] VIS-012-T06 [US2] GPU tests: initial state readback bit-identical across two reloads (generator recreated; settings decoded from their stored raw values via `ReactionDiffusionSettings(stored…)`; the UserDefaults round trip is in T10) and equal to the CPU seed, other seed differs; every preset at Speed 16 for 3 000 iterations at 128² with strong bass kicks every 0.25 s → full readback finite and in [0, 1], health clean; GPU follows the CPU reference for a few iterations; texture count, identities and allocatedSize constant over resizes, mode switches and reloads in Packages/VisualGenerators/Tests/VisualGeneratorsTests/ReactionDiffusionRenderTests.swift
- [ ] VIS-012-T07 [US1] Golden of a scripted run (Coral, Centre square, seed 1, speed 8, two bass kicks, 2 s), macOS host and iOS Simulator, in Packages/RenderGoldens/Tests/RenderGoldensTests/ReactionDiffusionGoldenTests.swift (+ GeneratorGoldens/ReactionDiffusion)

## Phase 4: US3 Bounded work, safe light (P1)

- [ ] VIS-012-T08 [US3] Flash tests: drawn pixels ≤ bound × gain ≤ 0.8; rapid reloads and bass bursts within the envelope budget and rise rate with Reduce flashing on and off; Reduce Motion halves iterations and spaces injections, in Packages/VisualGenerators/Tests/VisualGeneratorsTests/ReactionDiffusionFlashTests.swift

## Phase 5: US4 Choose and configure it (P2)

- [ ] VIS-012-T09 [US4] `VisualChoice.reactionDiffusion`, four keys `settings.reactionDiffusion.{preset,pattern,seed,speed}` in `AppSettings` (allKeys), host style `.reactionDiffusion(settings)` in place with the noise-field modes, accessibility value, coordinator and snapshot mapping, scene capture as no layer, `ReactionDiffusionOptions`, Settings text, VisualizerView change hook, offline renderer unchanged (bands only), FILE-005 `includedKeys` and `ALLOWED_KEYS` in Apps/projectM-iOS/…, Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py
- [ ] VIS-012-T10 [P] [US4] App tests (settings stored and restored with defaults for bad values, host builds the mode with the settings, in-place switches, reload on seed change, accessibility value, no scene layer) in Apps/projectM-iOS/Tests/ReactionDiffusionAppTests.swift; SettingsTests (`testOnlyTheSettingsKeysAreWritten`), LibraryBackupAppTests, CameraVisualTests updated and passing
- [ ] VIS-012-T11 [P] [US4] UI test (≤ 30 s): choose Reaction Diffusion, change the pattern, value names it, Bars hidden in Apps/projectM-iOS/UITests/ReactionDiffusionUITests.swift

## Phase 6: Polish

- [ ] VIS-012-T12 Repo checks, Linux shape build, type-check budget, privacy manifest and network symbols, PosterBoard counts, docs (RenderGoldens README) match the implementation
- [ ] VIS-012-T13 {device} D1: Reaction Diffusion with music; patterns grow per preset, bass plants growth, frame rate holds at Speed 16 on the PERF-001/007 overlay, no flashing on reloads with Reduce flashing on

## Dependencies

T02 → T03, T04 → T05 → T06, T07, T08 → T09 → T10, T11; T12 last. T13 needs a device.

## Parallel examples

T03 alongside T04; T07 and T08 after T05; T10 and T11 after T09.

## Implementation strategy

MVP = T02-T06 (the acceptance: reload reproduces the initial pattern; no NaN on the GPU). Then golden and safety, then the app.

## Analyze notes (speckit-analyze, 2026-11-15)

- Coverage: R1, R10 T04-T05; R2, R5, R7, R8, R12 T02-T03; R3, R4, R6, R9 T02-T06; R11, R12 T08; R13, R14 T09-T11;
  R15 T07. S1-S7 each have a test task (S3 in T03). No constitution conflict (no new compile site, no compute, no
  networking, nothing reaches projectM). 15 requirements, 13 tasks, 100 % coverage, 0 critical.
- Fix applied (ambiguity): plan's Performance Goals line rewritten (worst case 64 iterations per frame).
- Fix applied (underspecification): T06's "settings decoded from storage" names the stored raw values decoder; the
  UserDefaults round trip is asserted in T10.
