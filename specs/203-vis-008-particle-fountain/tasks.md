---
description: "Tasks for VIS-008 Particle fountain"
---

# Tasks: VIS-008 Particle Fountain

**Input**: `specs/203-vis-008-particle-fountain/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the spec (acceptance replay, ballistic closed form, bounds, Reduce Motion, flash
envelope, golden, UI test). Budgets (owner rule 7): a unit test ≈ 1-2 s (≤ 10 s), a package suite < 1 min,
the UI test < 30 s; no wall-clock assertions (clock injected).

Format: `- [ ] VIS-008-Txx [P?] [Story] description`. `{device}` = needs a physical device.

## Phase 1: Setup

- [ ] VIS-008-T01 Record the baseline: the PosterBoard report count; create the simulator "VIS8 iPhone 17" (iOS 27.2).

## Phase 2: Foundational

- [ ] VIS-008-T02 Implement `Packages/VisualGenerators/Sources/VisualGenerators/ParticleFountainConfiguration.swift`: gravity "R/s², 0.5…10, default 3.0; non-finite → default", drag "0…5, default 0.8", life "0.5…10, default 2.5", particle size "0.005…0.1, default 0.025", seed (default 0x5EED0008), Reduce Motion, palette, background; constants (data-model.md); `burstSize(strength:threshold:)` = 4 + round(20·clamp((s − θ)/0.25, 0, 1)), halved rounded up under Reduce Motion; the time-scaled effective values (R9); `SplitMix64`.

## Phase 3: User Story 2 — seeded and repeatable (P1, the acceptance)

- [ ] VIS-008-T03 [P] [US2] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/ParticleFountainSimulationTests.swift`: a fixed seed + onset log replayed twice → identical live/spawned counts and bitwise-identical particle state every frame (S1); 60 Hz vs 30 Hz vs irregular frames → equal counts and positions within 1e-9 at shared times (S2); another seed → same counts, different trajectories; ballistic closed form without drag within 1e-9, speed decreasing while rising with drag (S4); burst size monotone in 4…24, non-finite → 4 (S3); pool bound 512 and onset queue 32 under full-strength onsets every 50 ms for 10 s, counters (R5); death by age, floor and sides (R4); Reduce Motion halves bursts and launches at 0.7× with the apex within 1% (S6); `reset()` replays the same sequence; time going backwards and a long gap; SplitMix64 reference values.
- [ ] VIS-008-T04 [US2] Implement `ParticleFountainSimulation.swift` (contract C1). Evidence: T03 passes on the host and in the Linux shape.
- [ ] VIS-008-T05 [US2] Implement `ParticleFountainLayout.swift` (contract C2: squares, colours, alpha, `FlashRegionLayout`, no allocation per frame) with layout tests in `ParticleFountainSimulationTests.swift` (square positions and sizes for a known particle, alpha curve ≤ 0.8, zero and tiny sizes, storage addresses stable).
- [ ] VIS-008-T06 [US2] Implement `ParticleFountainGenerator.swift` (contract C2) and write `ParticleFountainRenderTests.swift` (Metal): no onsets → only background; a burst lights pixels above the emitter; `restartLoop()` clears the particles.
- [ ] VIS-008-T07 [US2] Write `Packages/RenderGoldens/Tests/RenderGoldensTests/ParticleFountainGoldenTests.swift` (catalog `particle-fountain`, research VIS-008-D8; integrity; determinism) and record the goldens in `Packages/RenderGoldens/GeneratorGoldens/ParticleFountain/{macos,ios-simulator}/`; README entry (VIS-008-R13, S7).
- [ ] VIS-008-T08 [P] [US2] Implement `Packages/VisualGenerators/Sources/VisualBandFeed/ParticleFountainTrigger.swift` (contract C3) with a test in `ParticleFountainSimulationTests.swift`: only `.onset` events map to (strength, threshold).

## Phase 4: User Story 3 — bounded, safe motion and light (P1)

- [ ] VIS-008-T09 [P] [US3] Write `ParticleFountainFlashTests.swift`: bursts alternating with silence at 60 Hz through `FlashSafetyLimiter` stay within the transition budget in all 17 areas with Reduce flashing on and off, with and without the strongest glow model, measured with `FlashAnalysis` (as `BeatRingFlashTests`) (VIS-008-R8, S5).

## Phase 5: User Story 1 — choose and see it in the app (P1)

- [ ] VIS-008-T10 [US1] App: `VisualChoice.particleFountain`, the key `settings.particleFountain.gravity` ("`low`/`medium`/`high`, anything else → medium") in `Apps/projectM-iOS/Coordinators/AppSettings.swift`; style mapping in `AppCoordinator.swift`; no layer in `ShowSceneSnapshot.swift` and `SceneAutosaveCapture.swift`; `NativeSpectrumHost.swift` style, palette, Reduce Motion, bus subscription and onset drain, accessibility value, in-place gravity change; Settings row and footer in `SettingsView.swift`; `onChange` in `VisualizerView.swift`; the key in `LibrarySettings.swift` and `scripts/run_device_tests.py`, reset by `-uitestResetNotice` (VIS-008-R10 to R12).
- [ ] VIS-008-T11 [US1] Write `Apps/projectM-iOS/Tests/ParticleFountainAppTests.swift` (settings round-trip and invalid values, key in all lists, host gravity change keeps the generator, Reduce Motion and palette reach the configuration, onsets drained into the fountain, accessibility value, scene capture records no layer) and update the native-visual lists in `SettingsTests.swift` and `CameraVisualTests.swift`.
- [ ] VIS-008-T12 [US1] Write `Apps/projectM-iOS/UITests/ParticleFountainUITests.swift` (< 30 s): choose Particle Fountain, Gravity offered with Medium selected, Bars hidden, choose High, the visual is shown with value "High gravity, …", source started once (VIS-008-S8).

## Phase 6: Polish

- [ ] VIS-008-T13 Full VisualGenerators suite on the host and in the Linux shape, RenderGoldens on the host (VIS-008-R14, S9); repo checks, privacy manifest and network symbols on the Debug app, type-check budget, PosterBoard count; delete the derived data and the simulator.
- [ ] VIS-008-T14 {device} On D1 with music, choose Particle Fountain: bursts follow onsets, arcs under gravity and drag, Reduce Motion fewer and slower; frame time in the performance overlay.

## Dependencies

T01 → T02 → T03 → T04 → T05 → T06 → (T07, T08, T09) → T10 → T11, T12 → T13.
US2 is the MVP (the roadmap acceptance); US1 needs US2's generator and T08's trigger.

## Parallel opportunities

T03, T08 and T09 (different files) can be written together once T02 exists.

## Implementation strategy

MVP: Phases 1-3 (the acceptance on the CPU and GPU). Then US3, then the app (US1), then polish.
