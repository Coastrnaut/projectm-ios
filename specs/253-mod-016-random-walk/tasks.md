# Tasks: MOD-016 Random walk modulator

**Input**: Design documents in `specs/253-mod-016-random-walk/` (spec.md, plan.md, research.md, data-model.md,
contracts/random-walk.md, quickstart.md).

**Tests**: test-first (the spec's acceptance is a test); the red run (compile failure) is recorded before the
production change. Budgets (owner rule 7): each unit test ≲ 1-2 s, each suite under 1 minute. Logs go to
`.build/scratch/mod-016/`.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. Inside descriptions "T03" is short for
`MOD-016-T03`. A task is ticked only with its evidence, " — Verified <date>: <how>" appended.

## Phase 1: Setup

- [ ] MOD-016-T01 Record the baseline: `swift test` for `Packages/ParameterGraph` and `Packages/SceneFormat` on the host (counts, failures); count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`.

## Phase 2: Foundational

- [ ] MOD-016-T02 Add `Packages/ParameterGraph/Sources/ParameterGraph/RandomWalk.swift`: `RandomWalk.ease(_ phi: Double, smoothness: Double) -> Double` = (1 − s)·φ + s·φ³·(φ·(6φ − 15) + 10), clamped to 0…1 (research D2, contract W3), and `RandomWalk.maximumSlope(smoothness:)` = (1 − s) + 1.875·s (research D3); Foundation-free.

## Phase 3: User Story 1 - smooth random motion that repeats for the same seed (P1) MVP

**Independent test**: `RandomWalkTests.testSameSeedAndTimebaseReproduceIdenticalValues` (MOD-016-R2, R3, S1).

- [ ] MOD-016-T03 [US1] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/RandomWalkTests.swift` (acceptance): banks with the same `randomWalk` settings and seed, driven at 60 Hz, 120 Hz and jittery frame times (deterministic pseudo-random gaps 1…40 ms) over ≥ 100 cycles, and direct seeks: identical values (exact `==`) at every shared time (the 60 Hz frame times shared with 120 Hz; every jittery time against a direct evaluation); equal to the contract W2 formula; a different seed differs; two unseeded slots differ; each cycle start reads its target exactly.
- [ ] MOD-016-T04 [US1] Implement `LFOShape.randomWalk` (stored name `randomWalk`), `LFO.smoothness` ("0…1, default 1", validated for every shape) and its value in `LFO.value(at:slot:)` per contract W2 in `Packages/ParameterGraph/Sources/ParameterGraph/LFO.swift`; update the shape switches in `LFOTests.swift` and `LFOSyncTests.swift`; T03 passes.

## Phase 4: User Story 2 - bounded and continuous (P1)

**Independent test**: `RandomWalkTests.testEveryValueStaysInBoundsOverTenHours`, `testFrameToFrameChangeIsBounded` (MOD-016-R4 to R6, S2, S3).

- [ ] MOD-016-T05 [US2] Bounds tests in `RandomWalkTests.swift`: for settings corners (centre 0, 0.5, 1; depth 0, 0.3, 1; smoothness 0, 0.5, 1; rates 0.01, 1, 20 Hz) a dense 60 Hz sweep of 2 minutes plus spot sweeps (1 s at 60 Hz) every hour up to 10 h: every value finite and within clamp(centre ± depth/2, 0, 1); between targets W never leaves [min, max] of the two targets (no overshoot); depth 0 holds the centre.
- [ ] MOD-016-T06 [US2] Continuity and ease tests in `RandomWalkTests.swift`: consecutive 60 Hz and jittery samples change by at most depth · maximumSlope · rate · Δt + 1e-12, including across cycle boundaries; `RandomWalk.ease` has e(0) = 0, e(1⁻) → 1, is monotone, smoothness 1 has a zero slope at both ends and smoothness 0 is linear; smoothness −0.1, 1.1, NaN refused.

## Phase 5: User Story 3 - stored, safe, live (P2)

**Independent test**: `SceneLFOTests` random walk round trip; `LFOBindingAppTests.testRandomWalkBindingDrivesTheGlowAlongItsTimeline`.

- [ ] MOD-016-T07 [US3] Synced continuity and Reduce flashing (`RandomWalkTests.swift`): a 1-beat synced random walk at 120 → 90 BPM continues without a jump (the change at the switch frame within the continuity bound, the step count continues); a 20 Hz random walk capped at 3 Hz reaches at most 3 new targets in one second.
- [ ] MOD-016-T08 [US3] Scene field in `Packages/SceneFormat/Sources/SceneFormat/SceneLFOs.swift` with tests in `Packages/SceneFormat/Tests/SceneFormatTests/SceneLFOTests.swift`: round trip keeps shape, smoothness and seed; smoothness 1 and every other shape write no `smoothness`; `smoothness` 1.5, −1, "x" → `invalidLFO`, entry kept; QA-004 meta-test passes.
- [ ] MOD-016-T09 [US3] App unit test in `Apps/projectM-iOS/Tests/LFOBindingAppTests.swift`: a seeded 2 Hz random walk on the glow through `NativeSpectrumHost` gives, every frame for 2 s, `lfo.value` at the frame's elapsed time (slot 0), stays within its bounds and changes by at most the continuity bound; run on the private iOS 27.2 simulator "MOD16 iPhone 17".

## Phase 6: Polish

- [ ] MOD-016-T10 Update the scene-document contract (`specs/059-scn-001-versioned-scene-format/contracts/scene-document.md`) and the file headers (`LFO.swift`, `SceneLFOs.swift`); confirm the new source imports no Foundation (Linux shape, MOD-016-R10) and `LFOBank.values` allocates nothing new per frame; run the repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), the type-check budget build, `LibraryBackupAppTests`, `check_privacy_manifest` and `check_network_symbols` on the Debug app, count PosterBoard reports; mark the spec Implemented.

## Dependencies

T01 → T02 → US1 (T03 → T04) → US2 (T05, T06) → US3 (T07 → T08, T09) → T10. US2 and US3 need T04.

## Parallel opportunities

T05 and T06 are independent test additions (same file, so sequential edits); T08 (SceneFormat) and T09 (app
test) touch different files once T04 is in.

## Implementation strategy

MVP = US1 (the roadmap acceptance's reproducibility), then US2 (its bounds), then persistence and the app
proof.
