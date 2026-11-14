---
description: "Tasks for VIS-006 Beat pulse rings"
---

# Tasks: VIS-006 Beat Pulse Rings

**Input**: `specs/186-vis-006-beat-rings/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the spec (acceptance, caps, flash envelope, golden, UI test). Budgets (owner
rule 7): a unit test ≈ 1-2 s (≤ 10 s), a package suite < 1 min, the UI test < 30 s; no wall-clock
assertions (clock injected).

Format: `- [ ] VIS-006-Txx [P?] [Story] description`. `{device}` = needs a physical device.

## Phase 1: Setup

- [X] VIS-006-T01 Record the baseline: the PosterBoard report count; create the simulator "VIS6 iPhone 17" (iOS 27.2). — Verified 2026-11-14: PosterBoard reports 25; simulator "VIS6 iPhone 17" (iOS 27.2) created.

## Phase 2: Foundational

- [X] VIS-006-T02 Implement `Packages/VisualGenerators/Sources/VisualGenerators/BeatRingConfiguration.swift`: `life` "0.5…5 s, default 1.5", `lineThickness` "0.001…0.05, default 0.015", palette, background; curve and cap constants; `minimumInterval(for:)`; non-finite → default (data-model.md). — Verified 2026-11-14: BeatRingFieldTests.testConfigurationClamps (out-of-range and non-finite values clamp or take defaults) and testCurvesStartAndEnd.

## Phase 3: User Story 2 — one independently timed ring per beat (P1, the acceptance)

- [X] VIS-006-T03 [P] [US2] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/BeatRingFieldTests.swift`: four beats at 0, 0.4, 0.8, 1.2 s sampled at 1.3 s → exactly 4 rings whose radius and alpha match R3 at their own ages within 1e-9; at 2.8 s → 0 rings; cap 16 drops the oldest; rate cap ≤ 3 per 1 s window with Reduce flashing (beats every 50 ms for 2 s), ≤ 6 without; out-of-order emissions ignored; determinism (replay identical); `reset()` clears (VIS-006-S1 to S3, R3 to R6). — Verified 2026-11-14: BeatRingFieldTests 7 pass on the host and in the Linux shape: four beats at 0/0.4/0.8/1.2 s give exactly 4 rings at 1.3 s whose radius and alpha match R3 at ages 1.3/0.9/0.5/0.1 s within 1e-9 (and a lone ring equals its counterpart), 0 rings at 2.8 s; cap keeps sequences 4…19 of 20; worst 1 s window 3 rings with Reduce flashing, 5 (≤ 6) without; replay identical.
- [X] VIS-006-T04 [US2] Implement `BeatRingField.swift` (contract C1). Evidence: T03 passes on the host and in the Linux shape. — Verified 2026-11-14: T03 passes on the host (swift test --filter BeatRing) and in the Linux shape (-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE, 12 tests, 0 failures).
- [X] VIS-006-T05 [US2] Implement `BeatRingLayout.swift` (contract C1) and write `BeatRingLayoutTests.swift`: 64 segments per live ring, segment midpoints at the ring's radius, colors by sequence with alpha, zero and tiny sizes, geometry identical on replay, storage addresses stable over frames; a life change applies from the next frame (R7, R14, edge case). — Verified 2026-11-14: BeatRingLayoutTests: 4 × 64 segments centred on each ring's radius with thickness T, colors by sequence with the ring's alpha, clockwise from the top, 1,536 vertices; size 0 draws nothing, 3 × 2 gives finite geometry; a fresh replay gives identical quads; storage addresses unchanged over 60 frames; rings stay inside the picture; a life change to 1.0 s drops the 1.3 s ring on the next layout.
- [X] VIS-006-T06 [US2] Implement `BeatRingGenerator.swift` (contract C2) and write `BeatRingRenderTests.swift` (Metal): four rings light pixels only near their radii; no rings → background only; `restartLoop()` clears the rings. — Verified 2026-11-14: BeatRingRenderTests passes on the host GPU: no beat lights nothing; four rings light pixels only within T/2 + 1.5 px of their radii and each younger ring is drawn; restartLoop() clears the rings.
- [X] VIS-006-T07 [US2] Write `Packages/RenderGoldens/Tests/RenderGoldensTests/BeatRingGoldenTests.swift` (catalog `beat-rings-four`; integrity; determinism) and record the goldens in `Packages/RenderGoldens/GeneratorGoldens/BeatRings/{macos,ios-simulator}/`; README entry (VIS-006-R12, S5). — Verified 2026-11-14: recorded with GOLDEN_RECORD=1 (host) and TEST_RUNNER_GOLDEN_RECORD=1 (VIS6, iOS 27.2), then verified without the switch: 2 captures identical on both classes (SSIM 1.0), integrity test passes; RenderGoldens 73 tests pass on the host (1 skipped, 11.2 s).

## Phase 4: User Story 3 — safe at any tempo (P1)

- [X] VIS-006-T08 [P] [US3] Write `BeatRingFlashTests.swift`: beats on every frame at 60 Hz (thick white rings, 1.5 s) through `FlashSafetyLimiter` and the generator's rate cap stay within the transition budget in all 17 areas with Reduce flashing on and off, with and without the strongest glow model, measured with `FlashAnalysis` (as `RadialWaveformFlashTests`) (VIS-006-R5, R8, S4). — Verified 2026-11-14: BeatRingFlashTests passes (0.7 s): worst transitions 0 portrait / 1 landscape with glow (limit 4) with Reduce flashing on, 5 of 90 beats became rings; 1 / 1 (limit 6) off, 9 of 90; rises within 0.25/s under Reduce flashing.
- [X] VIS-006-T09 [P] [US3] Implement `Packages/VisualGenerators/Sources/VisualBandFeed/BeatRingTrigger.swift` (contract C3) with tests in `BeatRingLayoutTests.swift`: a confident beat emits, a weak one does not; a kick emits without a recent confident beat and not within 2 s of one (so a beat and its kick give one ring, edge case); onsets and other transients never; a session marker forgets the beat (VIS-006-R2). — Verified 2026-11-14: BeatRingLayoutTests.testTriggerPrefersConfidentBeatsAndFallsBackToKicks: kick without a beat emits, weak beat does not, confident beat does, its kick 10 ms later does not, kick 2.1 s later does, onset and mid/high transients never, a session marker forgets the beat.

## Phase 5: User Story 1 — choose and see it in the app (P1)

- [X] VIS-006-T10 [US1] App: `VisualChoice.beatRings`, `BeatRingLife` (titles, seconds), key `settings.beatRings.life` ("`short`/`medium`/`long`, anything else → medium") in `Apps/projectM-iOS/Coordinators/AppSettings.swift`; style mapping in `AppCoordinator.swift`; no layer in `ShowSceneSnapshot.swift` and `SceneAutosaveCapture.swift`; `NativeSpectrumHost.swift` style, event drain through `BeatRingTrigger`, palette, accessibility value, in-place life change; Settings Ring life row and footer in `SettingsView.swift`; `onChange` in `VisualizerView.swift`; the key in `LibrarySettings.swift` and `scripts/run_device_tests.py`, reset by `-uitestResetNotice` (VIS-006-R9 to R11). — Verified 2026-11-14: build-for-testing on VIS6 succeeded with the type-check flags (no warning in changed code; SettingsView.swift:255 is a pre-existing closure); BeatRingsAppTests 4 pass.
- [X] VIS-006-T11 [US1] Write `Apps/projectM-iOS/Tests/BeatRingsAppTests.swift` (settings round-trip and invalid values, key in all lists, host style switch keeps the generator for a life change, accessibility value, scene capture records no layer) and update the native-visual lists in `SettingsTests.swift` and `CameraVisualTests.swift`. — Verified 2026-11-14: BeatRingsAppTests 4, SettingsTests, CameraVisualTests, RadialWaveformAppTests, LibraryBackupAppTests: 29 tests, 0 failures on VIS6; the life change keeps the same generator instance; the subscription exists only while beat rings are shown.
- [X] VIS-006-T12 [US1] Write `Apps/projectM-iOS/UITests/BeatRingsUITests.swift` (< 30 s): choose Beat Rings, Ring life offered with Medium selected, Bars hidden, choose Long, the visual is shown with value "Long ring life, …", source started once (VIS-006-S6). — Verified 2026-11-14: BeatRingsUITests passes on VIS6 in 14.4 s.

## Phase 6: Polish

- [X] VIS-006-T13 Full VisualGenerators suite on the host and in the Linux shape, RenderGoldens on the host (VIS-006-R13, S7); repo checks, privacy manifest and network symbols on the Debug app, type-check budget, PosterBoard count; delete the derived data and the simulator. — Verified 2026-11-14: VisualGenerators 202 tests pass on the host (40.8 s) and 169 in the Linux shape (34.1 s); RenderGoldens 73; LibraryBackup 74; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 OK; check_privacy_manifest and check_network_symbols OK on the Debug simulator app; PosterBoard 25 before and after; derived data and the simulator deleted.
- [ ] VIS-006-T14 {device} On D1 with music, choose Beat Rings: rings follow the beat; frame time in the performance overlay.

## Dependencies

T01 → T02 → T03 → T04 → T05 → T06 → (T07, T08); T09 independent after T02; T06, T09 → T10 → T11, T12 → T13.
US2 is the MVP (the roadmap acceptance); US1 needs US2's generator and US3's trigger.

## Parallel opportunities

T03 and T08/T09 (different files) can be written together once T02 exists.

## Implementation strategy

MVP: Phases 1-3 (the acceptance on the CPU and GPU). Then US3, then the app (US1), then polish.
