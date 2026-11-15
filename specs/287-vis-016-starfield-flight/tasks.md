# Tasks: VIS-016 Starfield Flight

**Input**: `specs/287-vis-016-starfield-flight/` (spec, plan, research, data-model, contracts/starfield.md)

## Phase 1: Foundational - model (VIS-016-R2 to R6)

- [ ] VIS-016-T01 `StarfieldSpeed`, `StarfieldConfiguration` (clamps, `activeCount`, constants) in `Packages/VisualGenerators/Sources/VisualGenerators/StarfieldConfiguration.swift`.
- [ ] VIS-016-T02 `StarfieldSimulation` (2000-star pool allocated once, SplitMix64 draws in fixed order, fixed 1/240 s steps from the anchor, ≤ 240 steps per advance, respawn, bass smoothing, `reset()`) in `StarfieldSimulation.swift`.

## Phase 2: User Stories 2 + 3 - density limit and deterministic reset (VIS-016-R2 to R4; S1, S2)

- [ ] VIS-016-T03 [US2] [US3] `StarfieldSimulationTests` (`Packages/VisualGenerators/Tests/VisualGeneratorsTests/StarfieldSimulationTests.swift`): 5000 requested → exactly 2000 active; never above over a 5 s run, storage address and size constant; reset → initial positions bit for bit; 60 Hz vs jittery frame times bit-identical at shared times; another seed differs; respawn at far with depth decreasing; Reduce Motion half; speed cap; Linux shape.

## Phase 3: User Stories 1 + 4 - layout and safety (VIS-016-R5, R7; S4)

- [ ] VIS-016-T04 [US1] `StarfieldLayout` (perspective squares, side and alpha bounds, fades, culling, total-light bound, flash regions, tessellation) in `StarfieldLayout.swift`.
- [ ] VIS-016-T05 [US1] [US4] `StarfieldFlashTests` (`StarfieldFlashTests.swift`): size and alpha never decrease as a star approaches (away from the fades); mean light ≤ 0.05 at 2000 stars, Fast, full bass; densest, fastest field with bass bursts within the envelope's transition budget in all 17 areas, Reduce flashing on and off (with the strongest glow).

## Phase 4: User Story 1 - the picture on Metal (VIS-016-R1, R9, R12; S3)

- [ ] VIS-016-T06 [US1] `StarfieldGenerator` on `FlatShapePass` (bands → low group → bass; advance; layout; envelope gain; tessellate) in `StarfieldGenerator.swift`.
- [ ] VIS-016-T07 [US1] `StarfieldRenderTests` (GPU, `StarfieldRenderTests.swift`): two renders identical; every lit pixel inside a laid-out square; restart gives the first frame again.
- [ ] VIS-016-T08 [US1] `StarfieldGoldenTests` + goldens in `Packages/RenderGoldens` (macOS host, iOS Simulator); README entry.

## Phase 5: User Story 5 - the app (VIS-016-R8, R10, R11; S5)

- [ ] VIS-016-T09 [US5] Visual choice `starfield`, keys `settings.starfield.speed` and `settings.starfield.density` (in `allKeys`, `ALLOWED_KEYS`, FILE-005 policy), `StarfieldOptions` (picker, stepper), host style `.starfield(speed:density:)` built and updated in place (`NativeSpectrumHost+Starfield.swift`), palette and Reduce Motion, accessibility value, scene capture as no layer.
- [ ] VIS-016-T10 [P] [US5] `StarfieldAppTests` (setting persists and falls back; host names itself, applies speed and density in place, palette and Reduce Motion; scene capture no layer); `SettingsTests`, `CameraVisualTests`, `LibraryBackupAppTests` updated and passing.
- [ ] VIS-016-T11 [P] [US5] `StarfieldUITests`: choose Starfield, Speed and Stars offered, Bars not, change speed, value updates, source started once (< 30 s).

## Phase 6: Polish

- [ ] VIS-016-T12 Touched package suites, Linux shape, RenderGoldens, repo checks, privacy manifest and network symbol scans, type-check budget, PosterBoard counts.
- [ ] VIS-016-T13 {device} On D1 with music, Starfield at 2000 stars and Fast holds the display's frame rate on the PERF-001/007 overlay, and looks calm with Reduce Motion.

## Dependencies

T01 → T02 → T03; T02 → T04 → T05, T06; T06 → T07, T08, T09 → T10, T11; all → T12. T13 needs a device.

## Parallel examples

T03 and T05 (different test files) after T04; T10 and T11 after T09.

## Implementation strategy

MVP = T01-T03 (the acceptance: density limit and deterministic reset, proven by pure simulation tests); then the
picture (T04-T08), then the app (T09-T11).
