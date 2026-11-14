---
description: "Tasks for VIS-005 Radial waveform"
---

# Tasks: VIS-005 Radial Waveform

**Input**: `specs/176-vis-005-radial-waveform/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the spec (acceptance fixtures, goldens, UI test). Budgets (owner rule 7): a
unit test ≈ 1-2 s (≤ 10 s), a package suite < 1 min, the UI test < 30 s; no wall-clock assertions.

Format: `- [ ] VIS-005-Txx [P?] [Story] description`. `{device}` = needs a physical device.

## Phase 1: Setup

- [ ] VIS-005-T01 Record the baseline: `swift test --package-path Packages/VisualGenerators` on the host, the PosterBoard report count; create the simulator "VIS5 iPhone 17" (iOS 27.2).

## Phase 2: Foundational

- [ ] VIS-005-T02 Implement `Packages/VisualGenerators/Sources/VisualGenerators/RadialWaveformConfiguration.swift`: `baseRadius` "0.2…0.75, default 0.55", `amplitude` "0…0.25, default 0.18", `lineThickness` "0.001…0.05, default 0.006", palette, background; non-finite → default; `clamped()` (data-model.md).

## Phase 3: User Story 2 — seamless ring that follows signed samples (P1, the acceptance)

- [ ] VIS-005-T03 [P] [US2] Write `RadialWaveformFixtures.swift` (mono histories: sine at a frequency and phase, DC, silence; distance helpers) and `RadialWaveformLayoutTests.swift` in `Packages/VisualGenerators/Tests/VisualGeneratorsTests/`: seam (97 Hz and 220 Hz sines at several end positions: max neighbour distance incl. the closing segment ≤ 1.5 × median; with the taper off > 5 × median); signed (DC +0.5 → every radius > R₀, −0.5 → every radius < R₀, silence → every radius = R₀ within 1e-12); the taper keeps a constant; determinism (10 frames bit-identical); clockwise from the top; points inside the inscribed circle at portrait, landscape, tiny and zero sizes; NaN reads 0; fewer samples than the window; palette colors oldest to newest; storage addresses stable (VIS-005-S1 to S3, R2 to R7, R14).
- [ ] VIS-005-T04 [US2] Implement `RadialWaveformLayout.swift` (contract C1) in `Packages/VisualGenerators/Sources/VisualGenerators/`. Evidence: T03 passes on the host and in the Linux shape.
- [ ] VIS-005-T05 [US2] Implement `RadialWaveformGenerator.swift` (contract C2) and write `RadialWaveformRenderTests.swift` (Metal): a sine ring lights pixels only within the ring band; silence lights the base circle only.
- [ ] VIS-005-T06 [US2] Write `Packages/RenderGoldens/Tests/RenderGoldensTests/RadialWaveformGoldenTests.swift` (catalog `radial-sine`, `radial-silence`; integrity test; determinism; the two differ) and record the goldens in `Packages/RenderGoldens/GeneratorGoldens/RadialWaveform/{macos,ios-simulator}/`; README entry (VIS-005-R12, S5).

## Phase 4: User Story 3 — flash safety (P2)

- [ ] VIS-005-T07 [P] [US3] Write `RadialWaveformFlashTests.swift`: a 60 Hz loud/silent alternation (thick white line, 2 s) through `FlashSafetyLimiter` stays within the transition budget with Reduce flashing on and off, with and without the strongest glow model, measured with `FlashAnalysis` (as `OscilloscopeFlashTests`); the gain holds and resets on `reset()` (VIS-005-R5, R8, S4).

## Phase 5: User Story 1 — choose and see it in the app (P1)

- [ ] VIS-005-T08 [US1] App: `VisualChoice.radialWaveform`, `RadialWaveformRing`/`RadialWaveformAmplitude` (titles, values), keys `settings.radialWaveform.ring` ("`small`/`medium`/`large`, anything else → medium") and `settings.radialWaveform.amplitude` ("`low`/`medium`/`high`, anything else → medium") in `Apps/projectM-iOS/Coordinators/AppSettings.swift`; style mapping in `AppCoordinator.swift`; no layer in `ShowSceneSnapshot.swift` and `SceneAutosaveCapture.swift`; `NativeSpectrumHost.swift` style, mono input, palette, accessibility value; Settings Ring and Amplitude rows and footer in `SettingsView.swift`; `onChange` in `VisualizerView.swift`; the keys in `LibrarySettings.swift` and `scripts/run_device_tests.py` (VIS-005-R9 to R11).
- [ ] VIS-005-T09 [US1] Write `Apps/projectM-iOS/Tests/RadialWaveformAppTests.swift` (settings round-trip and invalid values, keys in all lists, host style switch, accessibility value and palette, scene capture records no layer) and update the native-visual lists in `SettingsTests.swift` and `CameraVisualTests.swift`.
- [ ] VIS-005-T10 [US1] Write `Apps/projectM-iOS/UITests/RadialWaveformUITests.swift` (< 30 s): choose Radial Waveform, Ring and Amplitude offered with Medium selected, Bars hidden, choose Large, the visual is shown with value "Large ring, …", source started once (VIS-005-S6).

## Phase 6: Polish

- [ ] VIS-005-T11 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget, Linux shape build, PosterBoard count; delete the derived data and the simulator.
- [ ] VIS-005-T12 {device} On D1 with music, choose Radial Waveform and check frame time in the performance overlay.

## Dependencies

T01 → T02 → T03 → T04 → (T05, T07) → T06; T05 → T08 → T09, T10 → T11. US2 is the MVP (the roadmap
acceptance); US1 needs US2's generator.

## Parallel opportunities

T03 and T07 (different test files) can be written together once T02 exists; T06 and T07 are independent once T05 is done.

## Implementation strategy

MVP: Phases 1-3 (the acceptance on the CPU and GPU). Then US3, then the app (US1), then polish.
