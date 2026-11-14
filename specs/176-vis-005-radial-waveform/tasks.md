---
description: "Tasks for VIS-005 Radial waveform"
---

# Tasks: VIS-005 Radial Waveform

**Input**: `specs/176-vis-005-radial-waveform/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the spec (acceptance fixtures, goldens, UI test). Budgets (owner rule 7): a
unit test ≈ 1-2 s (≤ 10 s), a package suite < 1 min, the UI test < 30 s; no wall-clock assertions.

Format: `- [ ] VIS-005-Txx [P?] [Story] description`. `{device}` = needs a physical device.

## Phase 1: Setup

- [X] VIS-005-T01 Record the baseline: `swift test --package-path Packages/VisualGenerators` on the host, the PosterBoard report count; create the simulator "VIS5 iPhone 17" (iOS 27.2). — Verified 2026-11-14: at 5aaeebe5, VisualGenerators 157 tests pass on the host (27.8 s); PosterBoard reports 25; simulator "VIS5 iPhone 17" (iOS 27.2) created (.build/scratch/vis005/T01-*.log).

## Phase 2: Foundational

- [X] VIS-005-T02 Implement `Packages/VisualGenerators/Sources/VisualGenerators/RadialWaveformConfiguration.swift`: `baseRadius` "0.2…0.75, default 0.55", `amplitude` "0…0.25, default 0.18", `lineThickness` "0.001…0.05, default 0.006", palette, background; non-finite → default; `clamped()` (data-model.md). — Verified 2026-11-14: RadialWaveformLayoutTests.testConfigurationClampsAndStorageIsStable (out-of-range and non-finite values clamp or take defaults).

## Phase 3: User Story 2 — seamless ring that follows signed samples (P1, the acceptance)

- [X] VIS-005-T03 [P] [US2] Write `RadialWaveformFixtures.swift` (mono histories: sine at a frequency and phase, DC, silence; distance helpers) and `RadialWaveformLayoutTests.swift` in `Packages/VisualGenerators/Tests/VisualGeneratorsTests/`: seam (97 Hz and 220 Hz sines at several end positions: max neighbour distance incl. the closing segment ≤ 1.5 × median; with the taper off > 1.5 × median in every case, > 5 × in the worst); signed (DC +0.5 → every radius > R₀, −0.5 → every radius < R₀, silence → every radius = R₀ within 1e-12); the taper keeps a constant; determinism (10 frames bit-identical); clockwise from the top; points inside the inscribed circle at portrait, landscape, tiny and zero sizes; NaN reads 0; fewer samples than the window; palette colors oldest to newest; storage addresses stable (VIS-005-S1 to S3, R2 to R7, R14). — Verified 2026-11-14: RadialWaveformLayoutTests 9 pass on the host and in the Linux shape: seam ratio ≤ 1.5 for 97 and 220 Hz at three phases each (closing segment ≤ 1.5 × median); without the taper > 1.5 in every case and > 5 in the worst; DC +0.5 all radii > R₀, −0.5 all < R₀, silence all = R₀ within 1e-12; 10 frames bit-identical; storage addresses unchanged over 120 frames.
- [X] VIS-005-T04 [US2] Implement `RadialWaveformLayout.swift` (contract C1) in `Packages/VisualGenerators/Sources/VisualGenerators/`. Evidence: T03 passes on the host and in the Linux shape. — Verified 2026-11-14: T03 passes on the host (swift test --filter RadialWaveform) and in the Linux shape (-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE, 11 tests, 0 failures).
- [X] VIS-005-T05 [US2] Implement `RadialWaveformGenerator.swift` (contract C2) and write `RadialWaveformRenderTests.swift` (Metal): a sine ring lights pixels only within the ring band; silence lights the base circle only; `restartLoop()` resets the gain (pause/resume edge case). — Verified 2026-11-14: RadialWaveformRenderTests passes on the host GPU: silence lights only the base circle (within T/2 + 1.5 px), the sine ring stays within R₀ ± A and spans more than A; restartLoop() resets the gain.
- [X] VIS-005-T06 [US2] Write `Packages/RenderGoldens/Tests/RenderGoldensTests/RadialWaveformGoldenTests.swift` (catalog `radial-sine`, `radial-silence`; integrity test; determinism; the two differ) and record the goldens in `Packages/RenderGoldens/GeneratorGoldens/RadialWaveform/{macos,ios-simulator}/`; README entry (VIS-005-R12, S5). — Verified 2026-11-14: recorded with GOLDEN_RECORD=1 (host) and TEST_RUNNER_GOLDEN_RECORD=1 (VIS5, iOS 27.2), then verified without the switch: 4 captures identical on both classes, integrity test passes, sine ring and silence exceed QA-002's tolerance against each other; RenderGoldens 71 tests pass on the host (11.3 s).

## Phase 4: User Story 3 — flash safety (P2)

- [X] VIS-005-T07 [P] [US3] Write `RadialWaveformFlashTests.swift`: a 60 Hz loud/silent alternation (thick white line, 2 s) through `FlashSafetyLimiter` stays within the transition budget with Reduce flashing on and off, with and without the strongest glow model, measured with `FlashAnalysis` (as `OscilloscopeFlashTests`); the gain holds and resets on `reset()` (VIS-005-R5, R8, S4). — Verified 2026-11-14: RadialWaveformFlashTests 2 pass on the host (envelope test 3.1 s idle, 6.9 s at load average ≈ 900): worst transitions 1 / 1 (limit 4) with Reduce flashing on, 0 / 6 (limit 6) off; quiet sine reaches R₀ + A; gain holds and resets.

## Phase 5: User Story 1 — choose and see it in the app (P1)

- [X] VIS-005-T08 [US1] App: `VisualChoice.radialWaveform`, `RadialWaveformRing`/`RadialWaveformAmplitude` (titles, values), keys `settings.radialWaveform.ring` ("`small`/`medium`/`large`, anything else → medium") and `settings.radialWaveform.amplitude` ("`low`/`medium`/`high`, anything else → medium") in `Apps/projectM-iOS/Coordinators/AppSettings.swift`; style mapping in `AppCoordinator.swift`; no layer in `ShowSceneSnapshot.swift` and `SceneAutosaveCapture.swift`; `NativeSpectrumHost.swift` style, mono input, palette, accessibility value; Settings Ring and Amplitude rows and footer in `SettingsView.swift`; `onChange` in `VisualizerView.swift`; the keys in `LibrarySettings.swift` and `scripts/run_device_tests.py` (VIS-005-R9 to R11). — Verified 2026-11-14: build-for-testing on VIS5 succeeded; RadialWaveformAppTests 4 pass.
- [X] VIS-005-T09 [US1] Write `Apps/projectM-iOS/Tests/RadialWaveformAppTests.swift` (settings round-trip and invalid values, keys in all lists, host style switch (a ring or amplitude change keeps the same generator instance, edge case), accessibility value and palette, scene capture records no layer) and update the native-visual lists in `SettingsTests.swift` and `CameraVisualTests.swift`. — Verified 2026-11-14: RadialWaveformAppTests 4, SettingsTests, CameraVisualTests, LissajousAppTests, OscilloscopeAppTests, LibraryBackupAppTests: 32 tests, 0 failures on VIS5; the in-place change keeps the same generator instance.
- [X] VIS-005-T10 [US1] Write `Apps/projectM-iOS/UITests/RadialWaveformUITests.swift` (< 30 s): choose Radial Waveform, Ring and Amplitude offered with Medium selected, Bars hidden, choose Large, the visual is shown with value "Large ring, …", source started once (VIS-005-S6). — Verified 2026-11-14: RadialWaveformUITests passes on VIS5 in 16.9 s; LissajousUITests still passes (18.7 s).

## Phase 6: Polish

- [X] VIS-005-T11 Full VisualGenerators suite on the host and in the Linux shape, full RenderGoldens suite on the host (VIS-005-R13, S7); repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget, Linux shape build, PosterBoard count; delete the derived data and the simulator. — Verified 2026-11-14: VisualGenerators 169 tests pass on the host (67.3 s at load average ≈ 900) and 138 in the Linux shape (89.2 s); RenderGoldens 71 on the host; LibraryBackup 74; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 OK; check_privacy_manifest OK and check_network_symbols OK on the Debug simulator app; no type-check warning in changed code (warnings of 211-220 ms appear across untouched files at load average ≈ 900, including SettingsView.swift:251, a pre-existing closure); PosterBoard 25 before and after; derived data and the simulator deleted.
- [ ] VIS-005-T12 {device} On D1 with music, choose Radial Waveform and check frame time in the performance overlay.

## Dependencies

T01 → T02 → T03 → T04 → (T05, T07) → T06; T05 → T08 → T09, T10 → T11. US2 is the MVP (the roadmap
acceptance); US1 needs US2's generator.

## Parallel opportunities

T03 and T07 (different test files) can be written together once T02 exists; T06 and T07 are independent once T05 is done.

## Implementation strategy

MVP: Phases 1-3 (the acceptance on the CPU and GPU). Then US3, then the app (US1), then polish.
