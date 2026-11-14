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

- [ ] VIS-009-T01 Record the baseline: the PosterBoard report count; create the simulator "VIS9 iPhone 17" (iOS 27.2).

## Phase 2: Foundational

- [ ] VIS-009-T02 Implement `Packages/VisualGenerators/Sources/VisualGenerators/ParticleOrbitConfiguration.swift`: `particleCount` "16…256, default 160", `radius` "0.2…0.8, default 0.5", `bassDepth` "0…1, default 0.4", `angularSpeed` "0.1…3 rad/s, default 0.8", `particleSize` "0.005…0.1, default 0.022", seed 0x5EED0009, Reduce Motion, palette, background (non-finite → default); constants (data-model.md); `targetRadius(base:bass:depth:)` = clamp(base·(1 + depth·b), 0.15, 0.85), b clamped 0…1, non-finite → 0; effective τ, rate, pulse amplitude and speed scale under Reduce Motion.

## Phase 3: User Story 1 — bass-driven orbit (P1, the acceptance)

- [ ] VIS-009-T03 [P] [US1] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/ParticleOrbitSimulationTests.swift`: a synthetic bass timeline (steps 0 → 0.25 → 0.5 → 1 → 0, 0.5 s each, 60 Hz) → settled radius within 0.01 R of the mapped value and drawn radius (from the layout's squares) equal to it; larger bass never a smaller radius; bass 5, −1, NaN, ∞ stay within 0.15…0.85 and per-step change ≤ rate·Δt (S1); determinism (same seed/timeline bit-identical, other seed differs; S4); beats set the pulse and it decays; queue bound; Reduce Motion halves phase advance and lowers the pulse; reset; backwards time and long gaps.
- [ ] VIS-009-T04 [US1] Implement `ParticleOrbitSimulation.swift` (contract C1). Evidence: T03 on the host and in the Linux shape.
- [ ] VIS-009-T05 [US1] Implement `ParticleOrbitLayout.swift` (contract C2; centre square 0, particle squares, alpha ≤ 0.8, `FlashRegionLayout`, preallocated) with layout tests in T03's file (positions, sizes, zero and tiny sizes).
- [ ] VIS-009-T06 [US1] Add `visual.particleOrbit.radius` to `Packages/VisualGenerators/Sources/VisualParameters/VisualParameterCatalog.swift` (update `VisualParameterCatalogTests`) and implement `ParticleOrbitRadiusDrive.swift`; test in T03's file: with a MOD-002 binding (kick → radius 0.3…0.7) the drawn radius follows the binding's value within 0.01 R and the built-in bass is off; unbound → (setting, kick) (S2).

## Phase 4: User Story 2 — within the frame budget (P1)

- [ ] VIS-009-T07 [US2] Work-bound test in `ParticleOrbitSimulationTests.swift`: 256 particles, 600 frames at 60 Hz: ≤ 4 steps and ≤ 1,024 particle steps per frame, ≤ 257 squares and ≤ 1,542 tessellated vertices, storage addresses unchanged; a `measure` baseline reported, not asserted (S3).
- [ ] VIS-009-T08 [US2] Implement `ParticleOrbitGenerator.swift` (contract C2) and `ParticleOrbitRenderTests.swift` (Metal): the ring's lit pixels lie at the drawn radius; a bigger target draws a bigger ring; `restartLoop()` resets.
- [ ] VIS-009-T09 [US2] Write `Packages/RenderGoldens/Tests/RenderGoldensTests/ParticleOrbitGoldenTests.swift` (research D7) and record goldens in `Packages/RenderGoldens/GeneratorGoldens/ParticleOrbit/{macos,ios-simulator}/`; README entry (R13, S6).
- [ ] VIS-009-T10 {device} On D1 with music, choose Particle Orbit: ring swells on kicks, centre pulses on beats, Reduce Motion slower; the PERF-001/007 overlay shows the frame rate within budget (no more drops than the Mandala).

## Phase 5: User Story 3 — choose, control, safe (P1)

- [ ] VIS-009-T11 [P] [US3] Write `ParticleOrbitFlashTests.swift`: beats alternating with silence and kicks at 60 Hz through `FlashSafetyLimiter` stay within the transition budget in all 17 areas with Reduce flashing on and off, with and without the strongest glow (R8, S5).
- [ ] VIS-009-T12 [US3] App: `VisualChoice.particleOrbit`, key `settings.particleOrbit.radius` ("`small`/`medium`/`large`, anything else → medium") in `AppSettings.swift`; style mapping in `AppCoordinator.swift`; no layer in `ShowSceneSnapshot.swift`, `SceneAutosaveCapture.swift`; `NativeSpectrumHost.swift` style, palette, Reduce Motion, bus drain through `BeatRingTrigger`, per-frame drive after modulation, accessibility value, in-place radius change; Settings row; `VisualizerView` onChange; key in `LibrarySettings.swift`, `run_device_tests.py`, reset by `-uitestResetNotice` (R10 to R12).
- [ ] VIS-009-T13 [US3] Write `Apps/projectM-iOS/Tests/ParticleOrbitAppTests.swift` (settings round-trip, key lists, in-place radius, Reduce Motion and palette, drive from kick and from a binding, beats across a pause, accessibility value, scene capture) and update native lists in `SettingsTests.swift`, `CameraVisualTests.swift`.
- [ ] VIS-009-T14 [US3] Write `Apps/projectM-iOS/UITests/ParticleOrbitUITests.swift` (< 30 s): choose Particle Orbit, Radius with Medium, Bars hidden, choose Large, value "Large radius, …", source started once (S7).

## Phase 6: Polish

- [ ] VIS-009-T15 Full VisualGenerators suite on the host and in the Linux shape, RenderGoldens, catalog consumers (SceneFormat, app parameter tests), LibraryBackupAppTests; repo checks, privacy manifest and network symbols, type-check budget, PosterBoard count; delete the derived data and the simulator (R14, S8).

## Dependencies

T01 → T02 → T03 → T04 → T05 → T06 → T07 → T08 → (T09, T11) → T12 → T13, T14 → T15. T10 is device-only.

## Parallel opportunities

T03 and T11 (different files) once T02 exists.

## Implementation strategy

MVP: Phases 1-3 (the acceptance on the CPU). Then the budget and GPU (US2), then the app (US3), then polish.
