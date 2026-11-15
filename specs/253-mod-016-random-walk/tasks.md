# Tasks: MOD-016 Random walk modulator

**Input**: Design documents in `specs/253-mod-016-random-walk/` (spec.md, plan.md, research.md, data-model.md,
contracts/random-walk.md, quickstart.md).

**Tests**: test-first (the spec's acceptance is a test); the red run (compile failure) is recorded before the
production change. Budgets (owner rule 7): each unit test ≲ 1-2 s, each suite under 1 minute. Logs go to
`.build/scratch/mod-016/`.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. Inside descriptions "T03" is short for
`MOD-016-T03`. A task is ticked only with its evidence, " — Verified <date>: <how>" appended.

## Phase 1: Setup

- [X] MOD-016-T01 Record the baseline: `swift test` for `Packages/ParameterGraph` and `Packages/SceneFormat` on the host (counts, failures); count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`. — Verified 2026-11-14: at ae588a5d on the host: ParameterGraph 187 + 51 tests (1 skipped), 0 failures, 11 s wall; SceneFormat 196 tests, 0 failures, 19 s wall; PosterBoard reports 26 (.build/scratch/mod-016/T01-*.log).

## Phase 2: Foundational

- [X] MOD-016-T02 Add `Packages/ParameterGraph/Sources/ParameterGraph/RandomWalk.swift`: `RandomWalk.ease(_ phi: Double, smoothness: Double) -> Double` = (1 − s)·φ + s·φ³·(φ·(6φ − 15) + 10), clamped to 0…1 (research D2, contract W3), and `RandomWalk.maximumSlope(smoothness:)` = (1 − s) + 1.875·s (research D3); Foundation-free. — Verified 2026-11-14: RandomWalk.swift added (Foundation-free); testEaseIsMonotoneFromZeroToOne passes (e(0) = 0, e(1) = 1, monotone, slope within maximumSlope, s = 0 linear, s = 1 flat at both ends).

## Phase 3: User Story 1 - smooth random motion that repeats for the same seed (P1) MVP

**Independent test**: `RandomWalkTests.testSameSeedAndTimebaseReproduceIdenticalValues` (MOD-016-R2, R3, S1).

- [X] MOD-016-T03 [US1] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/RandomWalkTests.swift` (acceptance): banks with the same `randomWalk` settings and seed, driven at 60 Hz, 120 Hz and jittery frame times (deterministic pseudo-random gaps 1…40 ms) over ≥ 100 cycles, and direct seeks: identical values (exact `==`) at every shared time (the 60 Hz frame times shared with 120 Hz; every jittery time against a direct evaluation); equal to the contract W2 formula; a different seed differs; two unseeded slots differ; each cycle start reads its target exactly. — Verified 2026-11-14: written before the production code; red run `cannot find 'RandomWalk' in scope`, `type 'LFOShape?' has no member 'randomWalk'`, `extra argument 'smoothness'` (.build/scratch/mod-016/red-T03.log); now testSameSeedAndTimebaseReproduceIdenticalValues (1 201 shared 60/120 Hz times exactly equal, every jittery time equals a direct seek, a 1 h seek equals the run, a different seed differs in > 90% of frames), testUnseededSlotsDifferAndRepeat and testEachCycleStartReadsItsTargetExactly (through 10 h) pass.
- [X] MOD-016-T04 [US1] Implement `LFOShape.randomWalk` (stored name `randomWalk`), `LFO.smoothness` ("0…1, default 1", validated for every shape) and its value in `LFO.value(at:slot:)` per contract W2 in `Packages/ParameterGraph/Sources/ParameterGraph/LFO.swift`; update the shape switches in `LFOTests.swift` and `LFOSyncTests.swift`; T03 passes. — Verified 2026-11-14: `swift test` in Packages/ParameterGraph: 197 + 51 tests (1 skipped), 0 failures, 4 s wall; RandomWalkTests 10 tests in 0.14 s (.build/scratch/mod-016/T04-pg.log).

## Phase 4: User Story 2 - bounded and continuous (P1)

**Independent test**: `RandomWalkTests.testEveryValueStaysInBoundsOverTenHours`, `testFrameToFrameChangeIsBounded` (MOD-016-R4 to R6, S2, S3).

- [X] MOD-016-T05 [US2] Bounds tests in `RandomWalkTests.swift`: for settings corners (centre 0, 0.5, 1; depth 0, 0.3, 1; smoothness 0, 0.5, 1; rates 0.01, 1, 20 Hz) a dense 60 Hz sweep of 2 minutes plus spot sweeps (1 s at 60 Hz) every hour up to 10 h: every value finite and within clamp(centre ± depth/2, 0, 1); between targets W never leaves [min, max] of the two targets (no overshoot); depth 0 holds the centre. — Verified 2026-11-14: testEveryValueStaysInBoundsOverTenHours (81 setting corners, 641 520 samples, 0.10 s) and testTheWalkNeverOvershootsItsTwoTargets pass; a mutation (ease × 1.1, no clamp) makes both fail (.build/scratch/mod-016/mutation.log).
- [X] MOD-016-T06 [US2] Continuity and ease tests in `RandomWalkTests.swift`: consecutive 60 Hz and jittery samples change by at most depth · maximumSlope · rate · Δt + 1e-12, including across cycle boundaries; `RandomWalk.ease` has e(0) = 0, e(1⁻) → 1, is monotone, smoothness 1 has a zero slope at both ends and smoothness 0 is linear; smoothness −0.1, 1.1, NaN refused. — Verified 2026-11-14: testFrameToFrameChangeIsBounded (60 Hz and jittery, smoothness 0, 0.6, 1, 120 cycles; the largest observed rate exceeds 30% of the bound) and testSmoothnessIsValidated pass.

## Phase 5: User Story 3 - stored, safe, live (P2)

**Independent test**: `SceneLFOTests` random walk round trip; `LFOBindingAppTests.testRandomWalkBindingDrivesTheGlowAlongItsTimeline`.

- [X] MOD-016-T07 [US3] Synced continuity and Reduce flashing (`RandomWalkTests.swift`): a 1-beat synced random walk at 120 → 90 BPM continues without a jump (every frame's change within the continuity bound at the larger of the two rates, the step count continues: the targets after the switch are those of the following steps, none repeated); a 20 Hz random walk capped at 3 Hz reaches at most 3 new targets in one second. — Verified 2026-11-14: testSyncedWalkContinuesAcrossATempoChange (every frame equals the continued-cycle model within 1e-9 and stays within the 2 Hz bound) and testReduceFlashingCapsTheWalkAtThreeTargetsPerSecond (capped 20 Hz equals the 3 Hz walk exactly) pass.
- [X] MOD-016-T08 [US3] Scene field in `Packages/SceneFormat/Sources/SceneFormat/SceneLFOs.swift` with tests in `Packages/SceneFormat/Tests/SceneFormatTests/SceneLFOTests.swift`: round trip keeps shape, rate, sync, phase, amplitude (depth), centre, smoothness and seed exactly; smoothness 1 and every other shape write no `smoothness`; `smoothness` 1.5, −1, "x" → `invalidLFO`, entry kept; QA-004 meta-test passes. — Verified 2026-11-14: `swift test` in Packages/SceneFormat: 198 tests, 0 failures, 15 s wall (testRandomWalkRoundTripsEveryField, testInvalidSmoothnessIsReportedAndKept, SceneMigrationMatrixMetaTests pass) (.build/scratch/mod-016/T08-sf.log).
- [X] MOD-016-T09 [US3] App unit test in `Apps/projectM-iOS/Tests/LFOBindingAppTests.swift`: a seeded 2 Hz random walk on the glow through `NativeSpectrumHost` gives, every frame for 2 s, `lfo.value` at the frame's elapsed time (slot 0), stays within its bounds and changes by at most the continuity bound; run on the private iOS 27.2 simulator "MOD16 iPhone 17". — Verified 2026-11-14: build-for-testing on "MOD16 iPhone 17" (iOS 27.2) with the type-check budget flags (no warning in a touched file), then `test-without-building -only-testing:projectM-iOSTests/LFOBindingAppTests -only-testing:projectM-iOSTests/LibraryBackupAppTests`: 11 tests, 0 failures, 29 s wall; testRandomWalkBindingDrivesTheGlowAlongItsTimeline passed in 0.020 s (not skipped) (.build/scratch/mod-016/T09-*.log).

## Phase 6: Polish

- [X] MOD-016-T10 Update the scene-document contract (`specs/059-scn-001-versioned-scene-format/contracts/scene-document.md`) and the file headers (`LFO.swift`, `SceneLFOs.swift`); confirm the new source imports no Foundation (Linux shape, MOD-016-R10) and `LFOBank.values` allocates nothing new per frame; run the repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), the type-check budget build, `LibraryBackupAppTests`, `check_privacy_manifest` and `check_network_symbols` on the Debug app, count PosterBoard reports; mark the spec Implemented. — Verified 2026-11-14: contract paragraph in specs/059 scene-document.md; file headers in LFO.swift and SceneLFOs.swift; RandomWalk.swift and LFO.swift import no Foundation (C math only), `LFOBank.values` unchanged (no new per-frame allocation); check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 179 tests OK (1 skipped); check_privacy_manifest and check_network_symbols OK on the Debug simulator app; PosterBoard reports 26 before and 26 after. Linux build not run here (CI's Linux job).

## Dependencies

T01 → T02 → US1 (T03 → T04) → US2 (T05, T06) → US3 (T07 → T08, T09) → T10. US2 and US3 need T04.

## Parallel opportunities

T05 and T06 are independent test additions (same file, so sequential edits); T08 (SceneFormat) and T09 (app
test) touch different files once T04 is in.

## Implementation strategy

MVP = US1 (the roadmap acceptance's reproducibility), then US2 (its bounds), then persistence and the app
proof.
