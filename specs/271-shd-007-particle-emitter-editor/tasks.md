# Tasks: SHD-007 Particle Emitter Editor

**Input**: Design documents from `specs/271-shd-007-particle-emitter-editor/`
**Tests**: requested by the spec (acceptance is test-proven: a pure 10 s seeded simulation, a Metal golden, app and UI tests).

## Phase 1: Setup

- [X] SHD-007-T01 Create simulator "SHD7 iPhone 17" (iOS 27.2), run `xcodegen generate`, confirm the `Build` symlink and preset submodules in the worktree — Verified 2026-11-14: simulator SHD7 iPhone 17 (iOS 27.2) created, `xcodegen generate`, `Build` symlink and preset submodules present

## Phase 2: Foundational (blocks all stories)

- [X] SHD-007-T02 `ParticleEmitterSettings.swift` in VisualGenerators (shape, rate, speed, direction, spread, lifetime, gravity, bounds, action, restitution, seed; ranges, `clamped()`, lenient `Codable`, `rateMilli`) and `emitter` on `ParticleFountainConfiguration` (data-model.md) (SHD-007-R1, R2) — Verified 2026-11-14: `swift build` of VisualGenerators; `ParticleEmitterSettingsTests` pass
- [X] SHD-007-T03 [P] `ParticleEmitterSettingsTests.swift`: clamping of every range, non-finite → default, swapped min/max, lenient decode of damaged/partial JSON, rate resolution — Verified 2026-11-14: `ParticleEmitterSettingsTests` 3 tests pass (host and `-DVISUAL_NO_METAL`)

## Phase 3: User Story 2 - A seeded ten-second run is exact (P1) 🎯 acceptance

**Goal**: deterministic emitter physics. **Independent test**: `ParticleEmitterSimulationTests`.

- [X] SHD-007-T04 [US2] `ParticleFountainSimulation`: integer spawn accumulator, emitter spawn draws (shape, direction, speed, lifetime), emitter bursts, bounds (floor/box, bounce/kill), expiry stats; nil emitter unchanged (contract E1) (SHD-007-R3, R4, R5, R6) — Verified 2026-11-14: `ParticleEmitterSimulationTests` 5 pass; all 12 `ParticleFountainSimulationTests` and the whole VisualGenerators suite (326 tests) still pass
- [X] SHD-007-T05 [US2] `ParticleEmitterSimulationTests.swift`: 10 s at 60 Hz and jittery frames (spawn count exact, identical runs), lifetime bounds, box bounds never left, pool constant, seed same/different, overflow counted, rate 0, Reduce Motion halves the rate, VIS-008 tests still pass (SHD-007-S1, S2, S3) — Verified 2026-11-14: `ParticleEmitterSimulationTests.testTenSecondSeededRunMatchesSpawnCountAndLifetimeBounds` (375 spawns at 60 Hz and jittery frames, ages at death in [0.8, 1.6 + 1/60], zero particles outside the box, pool storage unchanged), `testFrameTimingDoesNotChangeTheRunAndSeedsDo`, `testAFullPoolDropsButTheAttemptsStayExact`, `testRateZeroReduceMotionAndKill` (187 under Reduce Motion), `testOnsetBurstsUseTheEmitterAndResetRestoresItsSeed`; 0.08 s in total

## Phase 4: User Story 3 - The configured emitter draws as expected (P2)

- [X] SHD-007-T06 [US3] `ParticleEmitterRenderTests.swift`: Metal frame of a configured emitter after 2 s: golden signature (lit-pixel count, mean), every lit pixel inside a laid-out square and the box; two renders identical — Verified 2026-11-14: `ParticleEmitterRenderTests` passes on the host GPU (golden 432 lit pixels, mean 2.9557; two renders byte-identical; every lit pixel inside the box and a laid-out square)

## Phase 5: User Story 1 - Shape the emitter and see it (P1)

- [X] SHD-007-T07 [US1] App: `ParticleEmitterChoice` (stored switch + settings, lenient JSON, seed sequence), `AppSettings.particleEmitter` with key `settings.particleFountain.emitter` in `allKeys`; key in `ALLOWED_KEYS`, `LibrarySettingsPolicy.includedKeys`; `SettingsTests.testOnlyTheSettingsKeysAreWritten` writes it (SHD-007-R8) — Verified 2026-11-14: `ParticleEmitterEditorTests.testChoicePersistsReadsLenientlyAndResets`, `SettingsTests` (9), `LibraryBackupAppTests`, `LibraryEraseAppTests` pass on SHD7 iPhone 17; LibraryBackup package 87 tests pass; `test_scripts.py` 179 OK
- [X] SHD-007-T08 [US1] Style plumbing: `NativeSpectrumStyle.particleFountain(gravity:emitter:)` in `AppCoordinator`, `SnapshotBatchJob`, `NativeSpectrumHost` (build and in place); `VisualizerView` change hook — Verified 2026-11-14: `ParticleEmitterEditorTests.testFountainStyleCarriesTheEmitterOnlyWhenOnAndTheHostAppliesIt`, `ParticleFountainAppTests` and `OfflineExportAcceptanceTests` pass on SHD7 iPhone 17
- [X] SHD-007-T09 [US1] `ParticleEmitterEditorView.swift`: link section in Settings, switch, preview (Canvas on a fixed 30 fps clock; paused under Reduce Motion with Step), Reset, seed stepper and New seed, ACC-005 sliders; footer for the Gravity picker (SHD-007-R7, R9) — Verified 2026-11-14: app builds for testing with the type-check flags (no long-body or long-expression warning); `ParticleEmitterEditorUITests` opens and drives the screen
- [X] SHD-007-T10 [P] [US1] `ParticleEmitterEditorTests.swift`: persistence round trip, damaged data, reset, the fountain style carries the emitter only when enabled, the preview model is deterministic — Verified 2026-11-14: `ParticleEmitterEditorTests` 4 tests pass in 1.7 s on SHD7 iPhone 17
- [X] SHD-007-T11 [US1] `ParticleEmitterEditorUITests.swift`: open the editor, turn on the switch, drag Rate and read it back (under 30 s) — Verified 2026-11-14: `ParticleEmitterEditorUITests.testSwitchAndRate` passed in 28.4 s on SHD7 iPhone 17 (preview runs, switch on, Rate 30 → higher)

## Phase 6: Polish

- [X] SHD-007-T12 Linux shape of VisualGenerators (`-DVISUAL_NO_METAL`), particle suites, app tests (`SettingsTests`, `LibraryBackupAppTests`), type-check budget, repo checks, privacy manifest and network symbols on the Debug app; spec status; delete simulator and derived data — Verified 2026-11-14: VisualGenerators 326 tests (80 s, pre-existing suite size) and the particle subsets under `-DVISUAL_NO_METAL` (21 tests); check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 179 OK; check_privacy_manifest OK and check_network_symbols OK on the Debug app
- [ ] SHD-007-T13 {device} Look at a box-bounce emitter at rate 120 on D1: particles stay inside the box, frame rate steady

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1 → T02, T04; R2 → T02, T03, T05 (pool); R3-R6 → T04, T05; R7 → T09, T11; R8 → T07, T08, T10; R9 → T09
(parameters only, no code input). S1-S3 → T05; S4 → T11; S5 → T12. No constitution conflicts. Fix applied: the
spec's Reduce Motion rule (rate halved) is now asserted in T05, and the Gravity picker footer (Clarifications) is
named in T09. No unmapped tasks; no duplicate requirements.
