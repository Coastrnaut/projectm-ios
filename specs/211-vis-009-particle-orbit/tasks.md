---
description: "Tasks for VIS-009 Particle orbit"
---

# Tasks: VIS-009 Particle Orbit

**Input**: `specs/211-vis-009-particle-orbit/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the spec (radius tracking, binding path, work bound, determinism, flash envelope,
GPU render, golden, UI test). Budgets (owner rule 7): a unit test ≈ 1-2 s (≤ 10 s), a package suite < 1 min,
the UI test < 30 s; no wall-clock assertions (clock injected).

Format: `- [ ] VIS-009-Txx [P?] [Story] description`. `{device}` = needs a physical device.

## Phase 1: Setup

- [X] VIS-009-T01 Record the baseline: the PosterBoard report count; create the simulator "VIS9 iPhone 17" (iOS 27.2). — Verified 2026-11-14: PosterBoard reports 26; simulator "VIS9 iPhone 17" (iOS 27.2, 95F6E66D) created.

## Phase 2: Foundational

- [X] VIS-009-T02 Implement `Packages/VisualGenerators/Sources/VisualGenerators/ParticleOrbitConfiguration.swift`: `particleCount` "16…256, default 160", `radius` "0.2…0.8, default 0.5", `bassDepth` "0…1, default 0.4", `angularSpeed` "0.1…3 rad/s, default 0.8", `particleSize` "0.005…0.1, default 0.022", seed 0x5EED0009, Reduce Motion, palette, background (non-finite → default); constants (data-model.md); `targetRadius(base:bass:depth:)` = clamp(base·(1 + depth·b), 0.15, 0.85), b clamped 0…1, non-finite → 0; effective τ, rate, pulse amplitude and speed scale under Reduce Motion. — Verified 2026-11-14: ParticleOrbitSimulationTests.testRadiusStaysBoundedAndRateLimitedForAnyInput (targetRadius clamps, NaN → 0.5) and testResetGapsBackwardsTimeAndSizes (configuration clamps).

## Phase 3: User Story 1 — bass-driven orbit (P1, the acceptance)

- [X] VIS-009-T03 [P] [US1] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/ParticleOrbitSimulationTests.swift`: a synthetic bass timeline (steps 0 → 0.25 → 0.5 → 1 → 0, 0.5 s each, 60 Hz) → settled radius within 0.01 R of the mapped value and drawn radius (from the layout's squares) equal to it; larger bass never a smaller radius; bass 5, −1, NaN, ∞ stay within 0.15…0.85 and per-step change ≤ rate·Δt (S1); determinism (same seed/timeline bit-identical, other seed differs; S4); beats set the pulse and it decays; queue bound; Reduce Motion halves phase advance and lowers the pulse; reset; backwards time and long gaps. — Verified 2026-11-14: ParticleOrbitSimulationTests 9 pass on the host (0.79 s) and in the Linux shape (-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE): settled radius 0.5/0.549988/0.599988/0.699976/0.500048 vs mapped 0.5/0.55/0.6/0.7/0.5 (≤ 0.01 R); drawn ring = radius × offset within 1e-9; settled radius monotone over bass 0…1; bass 5, −1, NaN, ±∞ stay in 0.15…0.85 with every step ≤ rate·Δt (normal and Reduce Motion); replays bit-identical, another seed differs; pulse e^(−t/0.2); queue 16 + 4 dropped.
- [X] VIS-009-T04 [US1] Implement `ParticleOrbitSimulation.swift` (contract C1). Evidence: T03 on the host and in the Linux shape. — Verified 2026-11-14: T03 passes on the host and in the Linux shape.
- [X] VIS-009-T05 [US1] Implement `ParticleOrbitLayout.swift` (contract C2; centre square 0, particle squares, alpha ≤ 0.8, `FlashRegionLayout`, preallocated) with layout tests in T03's file (positions, sizes, zero and tiny sizes). — Verified 2026-11-14: testDrawnRadiusTracks… (centres), testBeatsPulse… (core side 0.12 R, alphas ≤ 0.8), testResetGaps… (size 0 → none, 3×2 → ≥ 2 px).
- [X] VIS-009-T06 [US1] Add `visual.particleOrbit.radius` to `Packages/VisualGenerators/Sources/VisualParameters/VisualParameterCatalog.swift` (update `VisualParameterCatalogTests`) and implement `ParticleOrbitRadiusDrive.swift`; test in T03's file: with a MOD-002 binding (kick → radius 0.3…0.7) the drawn radius follows the binding's value within 0.01 R and the built-in bass is off; unbound → (setting, kick) (S2). — Verified 2026-11-14: testABindingOnTheRadiusParameterReplacesTheBuiltInBass: kick → radius 0.3…0.7 binding, radius 0.3/0.5/0.7/0.4 within 0.01 R, bass 0 when bound, (setting, kick) unbound; VisualParameterCatalogTests 4 pass with the new ID, group and range.

## Phase 4: User Story 2 — within the frame budget (P1)

- [X] VIS-009-T07 [US2] Work-bound test in `ParticleOrbitSimulationTests.swift`: 256 particles, 600 frames at 60 Hz: ≤ 4 steps and ≤ 1,024 particle steps per frame, ≤ 257 squares and ≤ 1,542 tessellated vertices, storage addresses unchanged; a `measure` baseline reported, not asserted (S3). — Verified 2026-11-14: testMaximumOrbitStaysWithinTheWorkBoundWithoutAllocating: 256 particles, 600 frames: exactly 4 steps per frame, ≤ 1,024 particle steps, ≤ 1,542 vertices, storage addresses unchanged; testWorkBaselineMetricIsReportedNotAsserted runs `measure` (reported only).
- [X] VIS-009-T08 [US2] Implement `ParticleOrbitGenerator.swift` (contract C2) and `ParticleOrbitRenderTests.swift` (Metal): the ring's lit pixels lie at the drawn radius; a bigger target draws a bigger ring; `restartLoop()` resets. — Verified 2026-11-14: ParticleOrbitRenderTests passes on the host GPU (0.10 s): lit ring pixels lie within radius × 0.9…1.1 (± half a square), 6 × 161 vertices, bass 1 draws a ring ≥ 0.1 R wider, restartLoop() returns the radius to 0.5.
- [X] VIS-009-T09 [US2] Write `Packages/RenderGoldens/Tests/RenderGoldensTests/ParticleOrbitGoldenTests.swift` (research D7) and record goldens in `Packages/RenderGoldens/GeneratorGoldens/ParticleOrbit/{macos,ios-simulator}/`; README entry (R13, S6). — Verified 2026-11-14: recorded, then `swift test --package-path Packages/RenderGoldens --filter ParticleOrbitGolden` (macOS host, 2 tests) and `xcodebuild test -scheme RenderGoldens` on an iOS 27.2 simulator (ParticleOrbitGoldenTests + integrity, 2 tests) pass with both frames identical (SSIM 1.0000).
- [ ] VIS-009-T10 {device} On D1 with music, choose Particle Orbit: ring swells on kicks, centre pulses on beats, Reduce Motion slower; the PERF-001/007 overlay shows the frame rate within budget (no more drops than the Mandala).

## Phase 5: User Story 3 — choose, control, safe (P1)

- [X] VIS-009-T11 [P] [US3] Write `ParticleOrbitFlashTests.swift`: beats alternating with silence and kicks at 60 Hz through `FlashSafetyLimiter` stay within the transition budget in all 17 areas with Reduce flashing on and off, with and without the strongest glow (R8, S5). — Verified 2026-11-14: ParticleOrbitFlashTests passes: worst transitions 1 portrait / 1 landscape with glow (limit 4) with Reduce flashing on, 3 / 2 (limit 6) off; rises within the rate under Reduce flashing.
- [X] VIS-009-T12 [US3] App: `VisualChoice.particleOrbit`, key `settings.particleOrbit.radius` ("`small`/`medium`/`large`, anything else → medium") in `AppSettings.swift`; style mapping in `AppCoordinator.swift`; no layer in `ShowSceneSnapshot.swift`, `SceneAutosaveCapture.swift`; `NativeSpectrumHost.swift` style, palette, Reduce Motion, bus drain through `BeatRingTrigger`, per-frame drive after modulation, accessibility value, in-place radius change; Settings row; `VisualizerView` onChange; key in `LibrarySettings.swift`, `run_device_tests.py`, reset by `-uitestResetNotice` (R10 to R12). — Verified 2026-11-14: `build-for-testing` of projectM-iOS for the iOS 27.2 simulator succeeds; ParticleOrbitAppTests (5) cover the setting, key lists, host style, palette, Reduce Motion, bus drain, in-place radius, the per-frame drive and scene capture; the UI-test reset uses `AppSettings.allKeys`, which holds the key.
- [X] VIS-009-T13 [US3] Write `Apps/projectM-iOS/Tests/ParticleOrbitAppTests.swift` (settings round-trip, key lists, in-place radius, Reduce Motion and palette, drive from kick and from a binding, beats across a pause, accessibility value, scene capture) and update native lists in `SettingsTests.swift`, `CameraVisualTests.swift`. — Verified 2026-11-14: ParticleOrbitAppTests 5 pass (drive: unbound target 0.5 at silence and 0.6 at kick 0.5; bound kick→radius 0.3…0.7 gives 0.3 with the built-in kick 1 ignored; unbind restores 0.7), with SettingsTests, CameraVisualTests, LibraryBackupAppTests, ParameterCatalogAppTests, SensorySafetyAppTests, ParameterShelfTests, MIDIMappingCoordinatorTests, SceneAutosaveCaptureTests, ParticleFountainAppTests: 67 tests, 0 failures, 4.7 s on the iOS 27.2 simulator.
- [X] VIS-009-T14 [US3] Write `Apps/projectM-iOS/UITests/ParticleOrbitUITests.swift` (< 30 s): choose Particle Orbit, Radius with Medium, Bars hidden, choose Large, value "Large radius, …", source started once (S7). — Verified 2026-11-14: ParticleOrbitUITests passes on the iOS 27.2 simulator in 28.5 s (Radius offered with Medium, Bars hidden, Large chosen, value "Large radius, …", sourceStarts 1).

## Phase 6: Polish

- [X] VIS-009-T15 Full VisualGenerators suite on the host and in the Linux shape, RenderGoldens, catalog consumers (SceneFormat, app parameter tests), LibraryBackupAppTests; repo checks, privacy manifest and network symbols, type-check budget, PosterBoard count; delete the derived data and the simulator (R14, S8). — Verified 2026-11-14: VisualGenerators 245 tests on the host (40.2 s) and 208 in the Linux shape (`-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`, 31.0 s); RenderGoldens 80 (1 skipped, 10.0 s); SceneFormat 168; LibraryBackup 77; app LibraryBackupAppTests, ParameterCatalogAppTests, MIDIMappingCoordinatorTests and the other catalog consumers pass (67 app tests); check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK, test_scripts 162 OK; check_privacy_manifest and check_network_symbols OK on the Debug simulator app; type-check budget: no warning in a changed expression or function (only load-inflated 206-220 ms readings in untouched code, load average above 60); PosterBoard 26 before and after; derived data and the VIS9 simulator deleted.

## Dependencies

T01 → T02 → T03 → T04 → T05 → T06 → T07 → T08 → (T09, T11) → T12 → T13, T14 → T15. T10 is device-only.

## Parallel opportunities

T03 and T11 (different files) once T02 exists.

## Implementation strategy

MVP: Phases 1-3 (the acceptance on the CPU). Then the budget and GPU (US2), then the app (US3), then polish.
