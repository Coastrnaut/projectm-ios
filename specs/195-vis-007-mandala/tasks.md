---
description: "Tasks for VIS-007 Mandala symmetry"
---

# Tasks: VIS-007 Mandala Symmetry

**Input**: `specs/195-vis-007-mandala/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the spec (acceptance, mirror, silence, rotation, flash envelope, golden, UI
test). Budgets (owner rule 7): a unit test ≈ 1-2 s (≤ 10 s), a package suite < 1 min, the UI test
< 30 s; no wall-clock assertions (clock injected).

Format: `- [ ] VIS-007-Txx [P?] [Story] description`. `{device}` = needs a physical device.

## Phase 1: Setup

- [X] VIS-007-T01 Record the baseline: the PosterBoard report count; create the simulator "VIS7 iPhone 17" (iOS 27.2). — Verified 2026-11-14: PosterBoard reports 25; simulator "VIS7 iPhone 17" (iOS 27.2) created.

## Phase 2: Foundational

- [X] VIS-007-T02 Implement `Packages/VisualGenerators/Sources/VisualGenerators/MandalaConfiguration.swift`: symmetry (3/4/5/6/8/12, else 6), mirror, petal style and profiles, turns per second "0…0.05, default 0.025", Reduce Motion halving, palette, background; band groups (R2); non-finite → default (data-model.md). — Verified 2026-11-14: MandalaLayoutTests.testConfigurationClampsAndReadsUnsupportedSymmetryAsSix (0, 1, 2, 7, 9, 13, −4 → 6; NaN speed → 0.025, 0.2 → 0.05; set later also clamped; profiles) and testBandGroupsClampAndSplit.

## Phase 3: User Story 2 — exact, deterministic symmetry (P1, the acceptance)

- [X] VIS-007-T03 [P] [US2] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/MandalaLayoutTests.swift`: the same bands and time at N = 4 and N = 8 → sectors 4 → 8, vertex count doubles exactly, every sector equals sector 0 rotated by 2πk/N within 1e-9, a repeat is bit-identical (S1); Mirror: second half = first half reflected across the sector centre line within 1e-9, vertices doubled (S2); silence → base shape (S3); band groups (out-of-range, NaN, fewer than 3 bands); unsupported symmetry → 6; petals inside their sector; zero and tiny sizes; storage addresses stable; a symmetry change applies from the next layout (R2 to R7, R14). — Verified 2026-11-14: MandalaLayoutTests 11 pass on the host and in the Linux shape: N = 4 → 4 sectors and 288 vertices, N = 8 → 8 sectors and 576 (mirrored 576 → 1,152); worst rotation error 1.1e-13 px for every supported N; fresh and repeated layouts bit-identical; mirror reflection error ≤ 1e-9; silence: tip 0.35, half-width 0.2σ, no curl, alpha 0.5; every corner inside its 12-fold wedge and the inscribed circle; storage addresses unchanged over 60 frames.
- [X] VIS-007-T04 [US2] Implement `MandalaLayout.swift` (contract C1). Evidence: T03 passes on the host and in the Linux shape. — Verified 2026-11-14: T03 passes on the host (swift test --filter Mandala) and in the Linux shape (-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE, 12 Mandala tests, 0 failures).
- [X] VIS-007-T06 [US2] Implement `MandalaGenerator.swift` (contract C2) and write `MandalaRenderTests.swift` (Metal): silence still draws the base shape; lit pixels have N-fold symmetry (pixel counts of the rotated image match); size change; `restartLoop()` keeps the rotation anchor (edge case: pause and resume continue from the clock). — Verified 2026-11-14: MandalaRenderTests 2 pass on the host GPU: silence lights > 50 pixels, none beyond the 0.35 tip; a 4-fold picture matches itself turned a quarter turn (≤ 3 % of lit pixels differ); after restartLoop() the angle at 10 s is 0.25 turns.
- [X] VIS-007-T07 [US2] Write `Packages/RenderGoldens/Tests/RenderGoldensTests/MandalaGoldenTests.swift` (catalog `mandala-six`; integrity; determinism) and record the goldens in `Packages/RenderGoldens/GeneratorGoldens/Mandala/{macos,ios-simulator}/`; README entry (VIS-007-R12, S6). — Verified 2026-11-14: recorded with GOLDEN_RECORD=1 (host) and TEST_RUNNER_GOLDEN_RECORD=1 (VIS7, iOS 27.2), then verified without the switch: 2 captures identical on both classes (SSIM 1.0), integrity test passes; RenderGoldens 76 tests pass on the host (1 skipped, 48.1 s).

## Phase 4: User Story 3 — safe motion and light (P1)

- [X] VIS-007-T05 [P] [US3] Rotation tests in `MandalaLayoutTests.swift`: the angle over 10 s of injected time never exceeds 0.05 turns per second (a configured 0.2 is capped); Reduce Motion gives exactly half the speed; toggling it keeps the angle continuous; time going backwards gives a finite angle (S5, R5, R6). — Verified 2026-11-14: testRotationIsCappedAndHalvedUnderReduceMotion (600 frames at 60 Hz: mean speed 0.025, 0.05 for a configured 0.2, 0.0125 and 0.025 with Reduce Motion, every frame clockwise and ≤ 0.05 turns/s) and testReduceMotionToggleKeepsTheAngleContinuous (no jump at either toggle, half speed between, backwards time finite).
- [X] VIS-007-T08 [P] [US3] Write `MandalaFlashTests.swift`: bands alternating silence and full scale on every frame at 60 Hz through `FlashSafetyLimiter` stay within the transition budget in all 17 areas with Reduce flashing on and off, with and without the strongest glow model, measured with `FlashAnalysis` (as `BeatRingFlashTests`) (VIS-007-R8, S4). — Verified 2026-11-14: MandalaFlashTests passes (0.8 s): worst transitions 1 portrait / 1 landscape mirrored with glow (limit 4) with Reduce flashing on; 6 / 6 (limit 6) off; rises within the rate under Reduce flashing.

## Phase 5: User Story 1 — choose and see it in the app (P1)

- [X] VIS-007-T09 [US1] App: `VisualChoice.mandala`, the three keys `settings.mandala.symmetry` (3/4/5/6/8/12, else 6), `settings.mandala.mirror`, `settings.mandala.petal` ("`petal`/`round`/`spike`, anything else → petal") in `Apps/projectM-iOS/Coordinators/AppSettings.swift`; style mapping and Reduce Motion in `AppCoordinator.swift`; no layer in `ShowSceneSnapshot.swift` and `SceneAutosaveCapture.swift`; `NativeSpectrumHost.swift` style, palette, Reduce Motion, accessibility value, in-place changes; Settings rows and footer in `SettingsView.swift`; `onChange` in `VisualizerView.swift`; the keys in `LibrarySettings.swift` and `scripts/run_device_tests.py`, reset by `-uitestResetNotice` (VIS-007-R9 to R11). — Verified 2026-11-14: build-for-testing on VIS7 succeeded with the type-check flags: no warning in changed code (196-209 ms warnings in untouched files under load, SettingsView.swift:257 and VisualizerView.swift:61 pre-existing); MandalaAppTests 4 pass.
- [X] VIS-007-T10 [US1] Write `Apps/projectM-iOS/Tests/MandalaAppTests.swift` (settings round-trip and invalid values, keys in all lists, host style switch keeps the generator, Reduce Motion reaches the configuration, accessibility value, palette, scene capture records no layer) and update the native-visual lists in `SettingsTests.swift` and `CameraVisualTests.swift`. — Verified 2026-11-14: MandalaAppTests 4, SettingsTests, CameraVisualTests, BeatRingsAppTests, RadialWaveformAppTests, LibraryBackupAppTests: 33 tests, 0 failures on VIS7; symmetry, mirror and petal change keep the same generator; Reduce Motion reaches the current and a rebuilt generator.
- [X] VIS-007-T11 [US1] Write `Apps/projectM-iOS/UITests/MandalaUITests.swift` (< 30 s): choose Mandala, Symmetry offered with 6 selected, Bars hidden, choose 8, the visual is shown with value "8-fold, …", source started once (VIS-007-S7). — Verified 2026-11-14: MandalaUITests passes on VIS7 in 15.3 s.

## Phase 6: Polish

- [X] VIS-007-T12 Full VisualGenerators suite on the host and in the Linux shape, RenderGoldens on the host (VIS-007-R13, S8); repo checks, privacy manifest and network symbols on the Debug app, type-check budget, PosterBoard count; delete the derived data and the simulator. — Verified 2026-11-14: VisualGenerators 219 tests pass on the host (52 s wall) and 184 in the Linux shape (32 s); RenderGoldens 76 (1 skipped); LibraryBackup 77; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 OK; check_privacy_manifest and check_network_symbols OK on the Debug simulator app; PosterBoard 25 before and after; derived data and the simulator deleted.
- [ ] VIS-007-T13 {device} On D1 with music, choose Mandala: petals follow the music, the slow turn; frame time in the performance overlay.

## Dependencies

T01 → T02 → T03 → T04 → T06 → (T05, T07, T08) → T09 → T10, T11 → T12.
US2 is the MVP (the roadmap acceptance); US1 needs US2's generator.

## Parallel opportunities

T03 and T08 (different files) can be written together once T02 exists.

## Implementation strategy

MVP: Phases 1-3 (the acceptance on the CPU and GPU). Then US3, then the app (US1), then polish.
