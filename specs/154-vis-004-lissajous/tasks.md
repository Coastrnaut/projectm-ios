---
description: "Tasks for VIS-004 Lissajous scope"
---

# Tasks: VIS-004 Lissajous Scope

**Input**: `specs/154-vis-004-lissajous/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the spec (acceptance fixtures, goldens, UI test). Budgets (owner rule 7): a
unit test ≈ 1-2 s (≤ 10 s), a package suite < 1 min, the UI test < 30 s; no wall-clock assertions.

Format: `- [ ] VIS-004-Txx [P?] [Story] description`. `{device}` = needs a physical device.

## Phase 1: Setup

- [X] VIS-004-T01 Record the baseline: `swift test --package-path Packages/VisualGenerators` on the host, the repo checks, the PosterBoard report count; create the simulator "VIS4 iPhone 17" (iOS 27.2). — Verified 2026-11-14: at 1fe5f95c, VisualGenerators 136 tests pass on the host (30.9 s); PosterBoard reports 25; simulator "VIS4 iPhone 17" (iOS 27.2) created (.build/scratch/vis004/T01-*.log).

## Phase 2: Foundational (stereo samples)

- [X] VIS-004-T02 [P] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/WaveformTapStereoTests.swift`: after reads the tap's `stereoOutput` holds the newest 2,048 frames interleaved (L, R), oldest first, zeros before the first frames; reads larger than the history keep the newest; the forwarded bytes and the mono `output` are unchanged; storage addresses stable (contract C1, VIS-004-R2, R16, R17). — Verified 2026-11-14: WaveformTapStereoTests 3 tests pass on the host and in the Linux shape (`-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`); VIS-003's WaveformTapTests 4 still pass.
- [X] VIS-004-T03 Implement the stereo history and `stereoOutput` in `Packages/VisualGenerators/Sources/VisualBandFeed/WaveformTap.swift`. Evidence: T02 and VIS-003's `WaveformTapTests` pass. — Verified 2026-11-14: T02 passes; mono history unchanged (WaveformTapTests, ChannelSelectionBandTests in the full suite, 157 tests, 0 failures).

## Phase 3: User Story 2 — distinguishable stable shapes (P1, the acceptance)

- [X] VIS-004-T04 [P] [US2] Write `LissajousFixtures.swift` (interleaved stereo histories: in-phase L = R sine, quadrature R = L shifted 90°, anti-phase, one channel silent, silence; principal-axis metric: covariance eigenvalues → minor/major ratio, radius mean and spread) and `LissajousLayoutTests.swift`: in-phase points on the diagonal (|u − v| < 1e-9), ratio < 0.02; quadrature ratio > 0.95, radius spread < 2 %, axes equal within 2 %; difference > 0.9; steady fixture identical on 10 frames; phase-advancing within 0.01; Mid/Side makes in-phase vertical and anti-phase horizontal; silence → 0 points and 0 vertices; NaN reads 0; tiny and zero sizes; points inside the output; segment colors follow the palette oldest to newest (VIS-004-R5) (VIS-004-S1, S2, R3, R4, R7). — Verified 2026-11-14: LissajousLayoutTests 7 pass on the host and in the Linux shape: in-phase |u − v| < 1e-9 and axis ratio < 0.02; quadrature ratio > 0.95, radius spread < 2 %, axis lengths within 2 %; difference > 0.9; identical metric on 10 steady frames, within 0.01 over 30 advancing frames.
- [X] VIS-004-T05 [US2] Implement `LissajousConfiguration.swift` (mode `xy`/`midSide`, `persistenceHalfLife` "0 (off) or 0.01…0.5", `lineThickness` "0.001…0.05, default 0.006", palette, background; `persistenceHalfLife(enabled:clamp:)`), `LissajousAutoGain.swift` (floor 0.01, hold 0.5 s, release half-life 0.5 s, Δt clamped to 0…0.1 s) and `LissajousLayout.swift` (contract C2) in `Packages/VisualGenerators/Sources/VisualGenerators/`. Evidence: T04 passes on the host and in the Linux shape. — Verified 2026-11-14: T04 and T08 pass on the host (swift test --filter Lissajous) and in the Linux shape (127 tests, 0 failures).
- [X] VIS-004-T06 [US2] Implement `LissajousGenerator.swift` (contract C3) and write `LissajousRenderTests.swift` (Metal): both fixtures draw; silence clears to the background; the in-phase picture has lit pixels only near the diagonal. — Verified 2026-11-14: LissajousRenderTests 3 pass on the host GPU: in-phase lit pixels within T/2 + 1.5 px of the diagonal, quadrature within the circle band, silence all black, a ghost fades from > 200 to < 100 and is gone after 4 half-lives.
- [X] VIS-004-T07 [US2] Write `Packages/RenderGoldens/Tests/RenderGoldensTests/LissajousGoldenTests.swift` (catalog `lissajous-inphase`, `lissajous-quadrature`; integrity test; GPU test as VIS-003's) and record the goldens in `Packages/RenderGoldens/GeneratorGoldens/Lissajous/{macos,ios-simulator}/` (VIS-004-R15, S5). — Verified 2026-11-14: recorded with GOLDEN_RECORD=1 (host) and TEST_RUNNER_GOLDEN_RECORD=1 (VIS4, iOS 27.2), then verified without the switch: 4 captures identical on both classes, integrity test passes, the two shapes exceed QA-002's tolerance against each other; RenderGoldens 62 tests pass on the host (5.9 s).

## Phase 4: User Story 3 — gain, silence, persistence, flash safety (P2)

- [X] VIS-004-T08 [P] [US3] Write `LissajousPersistenceTests.swift`: gain (0.05 sine reaches 90 % ± 1 %; hold 0.5 s then halves per 0.5 s, never below the peak; floor 0.01; Δt clamp); persistence (weights (0.5^(age/h) − 1/16)/(15/16) within 1e-9; none after 4 h; ≤ 8 snapshots; none taken in silence; mode change and off clear them; `reset()`); caps (`persistenceHalfLife(enabled:clamp:)` = 0.2 standard, 0.1 at intensity limit 0.2, ≤ 0.25 with Reduce flashing, 0 at cap 0, 0 disabled); FX-019: a 60 Hz loud/silent alternation (1.5 s) stays within 4 (Reduce flashing) and 6 transitions per second in every area; storage addresses stable over 120 frames (VIS-004-S3, S4, R6, R8, R9, R13, R17). Evidence: passes on the host and in the Linux shape. — Verified 2026-11-14: LissajousPersistenceTests 8 pass on the host (envelope test 1.6 s) and in the Linux shape (2.2 s): gain hold/release within 1e-9, weights within 1e-9 and 0 at 4 half-lives, caps 0.2/0.1/≤0.25/0, worst transitions within the budget with Reduce flashing on and off, storage addresses unchanged.

## Phase 5: User Story 1 — choose and see it in the app (P1)

- [X] VIS-004-T09 [US1] App: `VisualChoice.lissajous`, `LissajousMode` titles, keys `settings.lissajous.mode` ("`xy`/`midSide`, anything else → xy") and `settings.lissajous.persistence` ("Bool, absent → false") in `Apps/projectM-iOS/Coordinators/AppSettings.swift`; style mapping in `AppCoordinator.swift`; no layer in `ShowSceneSnapshot.swift` and `SceneAutosaveCapture.swift`; `NativeSpectrumHost.swift` style, stereo input, accessibility value and the clamp → half-life; Settings Plot and Persistence rows and footer in `SettingsView.swift`; `onChange` in `VisualizerView.swift`; the keys in `LibrarySettings.swift` and `scripts/run_device_tests.py` (VIS-004-R10 to R12, R14). — Verified 2026-11-14: build-for-testing on VIS4 succeeded; LissajousAppTests 4 pass (48 app unit tests in the run, 0 failures).
- [X] VIS-004-T10 [US1] Write `Apps/projectM-iOS/Tests/LissajousAppTests.swift` (settings round-trip and invalid values, keys in all lists, host style switch and accessibility value, half-life follows the safety clamp, scene capture records no layer) and update the native-visual lists in `SettingsTests.swift` and `CameraVisualTests.swift`. — Verified 2026-11-14: LissajousAppTests 4, SettingsTests 9, CameraVisualTests, OscilloscopeAppTests, LibraryBackupAppTests, NativeVisualTests, MemoryPressureAppTests, ColorBlindControlsTests: 48 tests, 0 failures on VIS4.
- [X] VIS-004-T11 [US1] Write `Apps/projectM-iOS/UITests/LissajousUITests.swift` (< 30 s): choose Lissajous, Plot offered with X/Y selected, Bars hidden, choose Mid/Side, the visual is shown with value "Mid/Side, …", source started once (VIS-004-S6). Relaunch persistence of both keys is T10's unit test (keeps the UI test under 30 s). — Verified 2026-11-14: LissajousUITests passes on VIS4 in 20.0 s; OscilloscopeUITests still passes (22.7 s).

## Phase 6: Polish

- [X] VIS-004-T12 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget, Linux shape build, PosterBoard count; delete the derived data and the simulator. — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 OK; check_privacy_manifest OK and check_network_symbols OK on the Debug simulator app; LibraryBackup 68 tests pass; no type-check warning in changed code (the warnings seen are in untouched files under a load average near 700); PosterBoard 25 before and after; derived data and the simulator deleted.
- [ ] VIS-004-T13 {device} On D1 with stereo music, choose Lissajous and check frame time in the performance overlay with Persistence on.

## Dependencies

T01 → T02 → T03 → T04 → T05 → (T06, T08) → T07; T03 + T06 → T09 → T10, T11 → T12. US2 is the MVP
(the roadmap acceptance); US1 needs US2's generator.

## Parallel opportunities

T02 and T04 (different test files) can be written together; T07 and T08 are independent once T06 is done.
