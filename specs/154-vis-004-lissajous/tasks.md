---
description: "Tasks for VIS-004 Lissajous scope"
---

# Tasks: VIS-004 Lissajous Scope

**Input**: `specs/154-vis-004-lissajous/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the spec (acceptance fixtures, goldens, UI test). Budgets (owner rule 7): a
unit test ≈ 1-2 s (≤ 10 s), a package suite < 1 min, the UI test < 30 s; no wall-clock assertions.

Format: `- [ ] VIS-004-Txx [P?] [Story] description`. `{device}` = needs a physical device.

## Phase 1: Setup

- [ ] VIS-004-T01 Record the baseline: `swift test --package-path Packages/VisualGenerators` on the host, the repo checks, the PosterBoard report count; create the simulator "VIS4 iPhone 17" (iOS 27.2).

## Phase 2: Foundational (stereo samples)

- [ ] VIS-004-T02 [P] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/WaveformTapStereoTests.swift`: after reads the tap's `stereoOutput` holds the newest 2,048 frames interleaved (L, R), oldest first, zeros before the first frames; reads larger than the history keep the newest; the forwarded bytes and the mono `output` are unchanged; storage addresses stable (contract C1, VIS-004-R2, R16, R17).
- [ ] VIS-004-T03 Implement the stereo history and `stereoOutput` in `Packages/VisualGenerators/Sources/VisualBandFeed/WaveformTap.swift`. Evidence: T02 and VIS-003's `WaveformTapTests` pass.

## Phase 3: User Story 2 — distinguishable stable shapes (P1, the acceptance)

- [ ] VIS-004-T04 [P] [US2] Write `LissajousFixtures.swift` (interleaved stereo histories: in-phase L = R sine, quadrature R = L shifted 90°, anti-phase, one channel silent, silence; principal-axis metric: covariance eigenvalues → minor/major ratio, radius mean and spread) and `LissajousLayoutTests.swift`: in-phase points on the diagonal (|u − v| < 1e-9), ratio < 0.02; quadrature ratio > 0.95, radius spread < 2 %, axes equal within 2 %; difference > 0.9; steady fixture identical on 10 frames; phase-advancing within 0.01; Mid/Side makes in-phase vertical and anti-phase horizontal; silence → 0 points and 0 vertices; NaN reads 0; tiny and zero sizes; points inside the output; segment colors follow the palette oldest to newest (VIS-004-R5) (VIS-004-S1, S2, R3, R4, R7).
- [ ] VIS-004-T05 [US2] Implement `LissajousConfiguration.swift` (mode `xy`/`midSide`, `persistenceHalfLife` "0 (off) or 0.01…0.5", `lineThickness` "0.001…0.05, default 0.006", palette, background; `persistenceHalfLife(enabled:clamp:)`), `LissajousAutoGain.swift` (floor 0.01, hold 0.5 s, release half-life 0.5 s, Δt clamped to 0…0.1 s) and `LissajousLayout.swift` (contract C2) in `Packages/VisualGenerators/Sources/VisualGenerators/`. Evidence: T04 passes on the host and in the Linux shape.
- [ ] VIS-004-T06 [US2] Implement `LissajousGenerator.swift` (contract C3) and write `LissajousRenderTests.swift` (Metal): both fixtures draw; silence clears to the background; the in-phase picture has lit pixels only near the diagonal.
- [ ] VIS-004-T07 [US2] Write `Packages/RenderGoldens/Tests/RenderGoldensTests/LissajousGoldenTests.swift` (catalog `lissajous-inphase`, `lissajous-quadrature`; integrity test; GPU test as VIS-003's) and record the goldens in `Packages/RenderGoldens/GeneratorGoldens/Lissajous/{macos,ios-simulator}/` (VIS-004-R15, S5).

## Phase 4: User Story 3 — gain, silence, persistence, flash safety (P2)

- [ ] VIS-004-T08 [P] [US3] Write `LissajousPersistenceTests.swift`: gain (0.05 sine reaches 90 % ± 1 %; hold 0.5 s then halves per 0.5 s, never below the peak; floor 0.01; Δt clamp); persistence (weights (0.5^(age/h) − 1/16)/(15/16) within 1e-9; none after 4 h; ≤ 8 snapshots; none taken in silence; mode change and off clear them; `reset()`); caps (`persistenceHalfLife(enabled:clamp:)` = 0.2 standard, 0.1 at intensity limit 0.2, ≤ 0.25 with Reduce flashing, 0 at cap 0, 0 disabled); FX-019: a 60 Hz loud/silent alternation (1.5 s) stays within 4 (Reduce flashing) and 6 transitions per second in every area; storage addresses stable over 120 frames (VIS-004-S3, S4, R6, R8, R9, R13, R17). Evidence: passes on the host and in the Linux shape.

## Phase 5: User Story 1 — choose and see it in the app (P1)

- [ ] VIS-004-T09 [US1] App: `VisualChoice.lissajous`, `LissajousMode` titles, keys `settings.lissajous.mode` ("`xy`/`midSide`, anything else → xy") and `settings.lissajous.persistence` ("Bool, absent → false") in `Apps/projectM-iOS/Coordinators/AppSettings.swift`; style mapping in `AppCoordinator.swift`; no layer in `ShowSceneSnapshot.swift` and `SceneAutosaveCapture.swift`; `NativeSpectrumHost.swift` style, stereo input, accessibility value and the clamp → half-life; Settings Plot and Persistence rows and footer in `SettingsView.swift`; `onChange` in `VisualizerView.swift`; the keys in `LibrarySettings.swift` and `scripts/run_device_tests.py` (VIS-004-R10 to R12, R14).
- [ ] VIS-004-T10 [US1] Write `Apps/projectM-iOS/Tests/LissajousAppTests.swift` (settings round-trip and invalid values, keys in all lists, host style switch and accessibility value, half-life follows the safety clamp, scene capture records no layer) and update the native-visual lists in `SettingsTests.swift` and `CameraVisualTests.swift`.
- [ ] VIS-004-T11 [US1] Write `Apps/projectM-iOS/UITests/LissajousUITests.swift` (< 30 s): choose Lissajous, Plot offered with X/Y selected, Bars hidden, choose Mid/Side, the visual is shown with value "Mid/Side, …", source started once (VIS-004-S6). Relaunch persistence of both keys is T10's unit test (keeps the UI test under 30 s).

## Phase 6: Polish

- [ ] VIS-004-T12 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget, Linux shape build, PosterBoard count; delete the derived data and the simulator.
- [ ] VIS-004-T13 {device} On D1 with stereo music, choose Lissajous and check frame time in the performance overlay with Persistence on.

## Dependencies

T01 → T02 → T03 → T04 → T05 → (T06, T08) → T07; T03 + T06 → T09 → T10, T11 → T12. US2 is the MVP
(the roadmap acceptance); US1 needs US2's generator.

## Parallel opportunities

T02 and T04 (different test files) can be written together; T07 and T08 are independent once T06 is done.
