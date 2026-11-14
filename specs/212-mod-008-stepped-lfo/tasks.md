# Tasks: MOD-008 Stepped LFO (square and sample-and-hold)

**Input**: Design documents in `specs/212-mod-008-stepped-lfo/` (spec.md, plan.md, research.md, data-model.md,
contracts/stepped-lfo.md, quickstart.md).

**Tests**: test-first (the spec's acceptance is a test); the red run (compile failure) is recorded before the
production change. Budgets (owner rule 7): each unit test ≲ 1-2 s, each suite under 1 minute. Logs go to
`.build/scratch/mod-008/`.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. Inside descriptions "T03" is short for
`MOD-008-T03`. A task is ticked only with its evidence, " — Verified <date>: <how>" appended.

## Phase 1: Setup

- [ ] MOD-008-T01 Record the baseline: `swift test` for `Packages/ParameterGraph` and `Packages/SceneFormat` on the host (counts, failures); count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`.

## Phase 2: Foundational

- [ ] MOD-008-T02 Add `Packages/ParameterGraph/Sources/ParameterGraph/SteppedRandom.swift`: `level(seed: UInt64, step: Int64) -> Double` in 0…<1 (SplitMix64 finalizer of mix(seed) &+ step, top 53 bits / 2⁵³; research D1) and `defaultSeed(slot:)` = 2³² + slot (research D2); and in `LFO.swift` the exact cycle function returning `LFOCycle(step: Int64, phase: Double)` from the same sum as the phase (research D3), with `phase(…)` delegating to it (MOD-007 and MOD-009 results bit-identical).

## Phase 3: User Story 1 - random steps that repeat for the same seed (P1) MVP

**Independent test**: `SteppedLFOTests.testSameSeedAndTimebaseYieldIdenticalStepValues` (MOD-008-R3 to R6, S1).

- [ ] MOD-008-T03 [US1] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/SteppedLFOTests.swift` (acceptance): two banks with the same sample-and-hold settings and seed, driven at 60 Hz, 120 Hz and jittery frame times (deterministic pseudo-random gaps 1…40 ms) over ≥ 100 steps, record each step's level: identical (exact `==`) in all three, and equal to `center + amplitude·(SteppedRandom.level(seed, n) − 0.5)`; a level holds within a step; a different seed gives a different sequence; two unseeded slots differ; step number exact after 10 h.
- [ ] MOD-008-T04 [US1] Implement `LFOShape.sampleHold`, `LFO.seed` (`UInt32?`, nil = position default), `LFO.glide` ("0…1, default 0"), `LFO.value(at: LFOCycle, slot:)` and slot-aware `LFOBank.values` in `Packages/ParameterGraph/Sources/ParameterGraph/LFO.swift`; T03 passes.
- [ ] MOD-008-T05 [US1] Glide test and implementation: with glide g the value at phase φ < g is the linear ramp from level(n − 1) to level(n), at φ ≥ g the held level; glide outside 0…1 or NaN refused (`SteppedLFOTests`, `LFO.swift`).

## Phase 4: User Story 2 - square with duty cycle (P1)

**Independent test**: `SteppedLFOTests.testSquareTransitionsLandExactlyAtDutyBoundaries` (MOD-008-R2, S2).

- [ ] MOD-008-T06 [US2] Test and implement `LFOShape.square` and `LFO.dutyCycle` ("0.05…0.95, default 0.5"): for duty 0.25, 0.5, 0.8 a free 1 Hz square is high 1 ns before the duty boundary, low at and after it, low 1 ns before the cycle boundary and high at it; duty 0.04, 0.96, NaN refused (`SteppedLFOTests`, `LFO.swift`).
- [ ] MOD-008-T07 [US2] Update the shape switches in `Packages/ParameterGraph/Tests/ParameterGraphTests/LFOTests.swift` and `LFOSyncTests.swift` so the suites build with the new cases.

## Phase 5: User Story 3 - stored, safe, live (P2)

**Independent test**: `SceneLFOTests` stepped round trip; `LFOBindingAppTests.testSampleAndHoldBindingHoldsItsLevelsOnTheGlow`.

- [ ] MOD-008-T08 [US3] Synced continuity and Reduce flashing (`SteppedLFOTests`, `LFO.swift`): `LFOPhaseSegment.startCycle`; a 1-beat synced sample-and-hold at 120 → 90 BPM continues the step count (consecutive steps, no repeat, no restart); a 20 Hz stepped oscillator capped at 3 Hz steps at most 3 times in one second.
- [ ] MOD-008-T09 [US3] Scene fields in `Packages/SceneFormat/Sources/SceneFormat/SceneLFOs.swift` with tests in `Packages/SceneFormat/Tests/SceneFormatTests/SceneLFOTests.swift`: round trip keeps shape, duty, seed, glide; sine/triangle entries write no new key; `duty` 0.99, `glide` 2, `seed` −1 / 1.5 / 2³² → `invalidLFO`, entry kept; QA-004 meta-test passes.
- [ ] MOD-008-T10 [US3] App unit test in `Apps/projectM-iOS/Tests/LFOBindingAppTests.swift`: a seeded 2 Hz sample-and-hold on the glow through `NativeSpectrumHost` gives, every frame, `lfo.value` of the current step (slot 0), constant within a step; run on the private iOS 27.2 simulator.

## Phase 6: Polish

- [ ] MOD-008-T11 Update the scene-document contract (`specs/059-scn-001-versioned-scene-format/contracts/scene-document.md`) and the file headers; confirm the new source imports no Foundation (Linux shape, MOD-008-R10; CI's Linux job builds it) and `LFOBank.values` allocates nothing new per frame; run the repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), the type-check budget build, `LibraryBackupAppTests`, and count PosterBoard reports; mark the spec Implemented.

## Dependencies

T01 → T02 → US1 (T03 → T04 → T05) → US2 (T06, T07) → US3 (T08 → T09, T10) → T11. US2 needs only T02; it is
ordered after US1 because both edit `LFO.swift`.

## Parallel opportunities

T09 (SceneFormat) and T10 (app test) touch different files once T04 and T06 are in.

## Implementation strategy

MVP = US1 (the roadmap acceptance). Then square, then persistence and the app proof.
