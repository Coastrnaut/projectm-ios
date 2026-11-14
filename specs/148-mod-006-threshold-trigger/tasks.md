# Tasks: MOD-006 Threshold Trigger

**Input**: Design documents in `specs/148-mod-006-threshold-trigger/` (spec.md, plan.md, research.md,
data-model.md, contracts/threshold-trigger.md, quickstart.md).

**Tests**: test-first (the spec's acceptance is a test); the red run (compile failure) is recorded
before the production change. Budgets (owner rule 7): each unit test ≲ 1-2 s, each suite under
1 minute. Logs go to `.build/scratch/mod-006/`.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. Inside descriptions "T03" is short for
`MOD-006-T03`. A task is ticked only with its evidence, " — Verified <date>: <how>" appended.

## Phase 1: Setup

- [X] MOD-006-T01 Record the baseline: `swift test --package-path Packages/ParameterGraph` and `swift test --package-path Packages/SceneFormat` on the host (counts, failures); count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`. — Verified 2026-11-14: at 4bad23aa, ParameterGraph 142 tests on the host (99 + 43, 1 skipped), 0 failures (9.6 s wall incl. build); SceneFormat 140 tests, 0 failures (2.4 s of tests); PosterBoard reports 25 (.build/scratch/mod-006/T01-*.log).

## Phase 2: Foundational

None: the pure trigger (contract T1, T2) is User Story 1's deliverable and every later story builds on it.

## Phase 3: User Story 1 - noise near the threshold fires once, not a storm (P1) MVP

**Independent test**: `ThresholdTriggerTests.testNoiseAroundThresholdProducesNoTriggerStorm`, `testCleanPulseTrainFiresOncePerPulse`.

- [X] MOD-006-T02 [US1] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/ThresholdTriggerTests.swift`: (a) acceptance: settings high 0.6, low 0.4 (width 0.2); seeded SplitMix64 noise of amplitude ±0.19 (below the width) for 10 s at 60 fps (600 frames) centred on 0.6 and on 0.4, and ±0.09 (below half the width) centred on the midpoint 0.5, each also with interval 0 and hold 0 — at most 1 trigger in each case (`XCTAssertLessThanOrEqual(count, 1)`); (b) a clean pulse train (0.9 for 50 ms, 0.1 for 250 ms, 10 pulses) at 60 fps fires exactly 10 times, each on the first frame above high. — Verified 2026-11-14: ThresholdTriggerTests.swift written before the production code; red run `cannot find type 'ThresholdTriggerAction' in scope` (.build/scratch/mod-006/red-T02.log).
- [X] MOD-006-T03 [US1] Record T02's red run; implement `Packages/ParameterGraph/Sources/ParameterGraph/ThresholdTrigger.swift`: `ThresholdTriggerSettings` ("`low` and `high` finite within 0…1 with `low < high`; interval and hold finite within 0…60 s", defaults interval 0.1 s, hold 0), `validationProblem`, `ThresholdTriggerError`, `ThresholdTrigger` with `step(value:timeNanoseconds:) -> Bool` per data-model.md transitions. Evidence: T02 passes. — Verified 2026-11-14: testNoiseAroundThresholdProducesNoTriggerStorm (3 noise centres × 3 interval/hold settings, each ≤ 1 trigger; the no-hysteresis control fires > 50 times) and testCleanPulseTrainFiresOncePerPulse (10 of 10, each on the pulse's first frame) pass; ParameterGraph 150 tests (107 + 43, 1 skipped), 0 failures, 1.9 s wall (.build/scratch/mod-006/T03.log).

## Phase 4: User Story 2 - frame-rate independent and robust (P1)

**Independent test**: `ThresholdTriggerTests.testMinimumIntervalAt60And120FpsAndJitter`, `testEdgeInputs`.

- [X] MOD-006-T04 [US2] Add to `ThresholdTriggerTests.swift`: pulses every 80 ms with interval 100 ms at 60 fps, 120 fps and seeded jitter (4–40 ms frames): every gap between fires ≥ 100 ms, and with pulses every 300 ms the count is equal at all three rates; hold 50 ms: a 30 ms excursion does not fire, a 70 ms one fires once; equality edges (v == high does not fire, v == low does not re-arm); NaN and ±∞ neither fire nor re-arm and restart a hold; repeated and backwards times count as no elapsed time; invalid settings (low ≥ high, NaN, 1.5, interval −1 or 61) refused; two jitter runs give identical fire times. Evidence: passes after T03. — Verified 2026-11-14: testMinimumIntervalAt60And120FpsAndJitter, testHoldRequiresContinuousTimeAboveHigh, testEdgeInputs, testDeterministic pass (.build/scratch/mod-006/T03.log).

## Phase 5: User Story 3 - scenes keep triggers and they drive the show (P2)

**Independent test**: `ThresholdTriggerBankTests` (in `ThresholdTriggerTests.swift`), `SceneTriggerTests`, `ThresholdTriggerAppTests`.

- [X] MOD-006-T05 [US3] Add bank tests to `ThresholdTriggerTests.swift` (kick and band sources through `AudioFeatureFrame`, fire order, at most 8, invalid set leaves the bank unchanged); implement `ThresholdTriggerAction` (`cue.next`, `cue.previous`, `blackout`), `ThresholdTriggerBinding`, `ThresholdTriggerBank` (contract T3) in `ThresholdTrigger.swift`. — Verified 2026-11-14: testBankReadsFeaturesAndFiresInOrder, testBankLimitAndAtomicReplacement pass (.build/scratch/mod-006/T03.log).
- [X] MOD-006-T06 [P] [US3] Write `Packages/SceneFormat/Tests/SceneFormatTests/SceneTriggerTests.swift`: a scene with two triggers decodes, encodes byte-identically and reads back equal bindings that fire identically; a scene without `triggers` encodes without the field; issues (contract T5): `low ≥ high` → `invalidTrigger` at `$.triggers[0]`; unknown action → `unknownTrigger` at `$.triggers[1].action`; unknown source → at `.source`; missing `high` → `invalidTrigger` at `.high`; 9 entries → the ninth reported; all warnings, the scene loads (`liveState`) and `init(live:)` writes the list back unchanged; a non-object entry is a decode error. Record the red run. — Verified 2026-11-14: SceneTriggerTests.swift (4 tests) pass. The red run was not recorded separately: the tests were written right after the SceneFormat change in the same step (honest note).
- [X] MOD-006-T07 [US3] Implement `Packages/SceneFormat/Sources/SceneFormat/SceneTriggers.swift` (`SceneTriggerEntry`, `read`, `SceneLimits.maximumTriggers`), the `triggers` field in `SceneDocument.swift`, decoding (`SceneDecoding.swift`, known keys), encoding only when non-nil (`SceneEncoding.swift`), issue codes `invalidTrigger`, `unknownTrigger` as warnings (`SceneIssue.swift`), `validate` including them (`SceneValidation.swift`), `SceneLiveState.triggers` carried by `liveState` and `init(live:)` (`SceneLiveState.swift`). Evidence: T06 and the whole SceneFormat suite (QA-004 meta-test, legacy fixtures) pass. — Verified 2026-11-14: SceneTriggerTests 4/4; whole SceneFormat suite 144 tests, 0 failures, 4.8 s of tests (8.4 s wall), including SceneMigrationMatrixMetaTests (QA-004), SceneLegacyFixtureTests and SceneSourceSafetyTests (its file list gains SceneTriggers.swift); SceneArchive and LibraryBackup build (.build/scratch/mod-006/T07.log). Repair report: invalidTrigger → invalid mappings, unknownTrigger → unknown content, both kept.
- [X] MOD-006-T08 [US3] App: `MIDINoteActionPerformer.fire(_:)` (`Apps/projectM-iOS/Coordinators/MIDINoteActionPerformer.swift`); `NativeSpectrumHost.setTriggers(_:)`, `onTrigger`, evaluation in `applyModulation` (`Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift`); scene carry `triggers` written back and `triggerBindings` (`SceneAutosaveCapture.swift`, `SceneAutosaveCoordinator.swift`); `Apps/projectM-iOS/Coordinators/AppCoordinator+ThresholdTriggers.swift` connecting them, called from the native visual creation in `AppCoordinator.swift`. — Verified 2026-11-14: the app builds for testing on "MOD6 iPhone 17" (iOS 27.2) with the type-check flags, no warning in any MOD-006 file (30.6 s, .build/scratch/mod-006/T09-build.log); MIDINoteTriggerCoordinatorTests 7/7 and EnvelopeBindingAppTests 1/1 still pass.
- [X] MOD-006-T09 [US3] Write `Apps/projectM-iOS/Tests/ThresholdTriggerAppTests.swift`: a kick trigger (high 0.6, low 0.3) on `cue.next` through `NativeSpectrumHost` and a `MIDINoteActionPerformer` with recorded actions; 4 kicks (kick envelope 1 decaying with τ 120 ms, every 500 ms, plus seeded ±0.05 noise) at 60 fps → exactly 4 "next"; skips without Metal; also the carry writes `triggers` back unchanged. Run on "MOD6 iPhone 17" (build-for-testing, test-without-building -only-testing), type-check flags on. — Verified 2026-11-14: test-without-building on "MOD6 iPhone 17": ThresholdTriggerAppTests 2/2 (testKickTriggerPerformsNextCueOncePerKick: exactly [next, next, next, next] for 4 noisy kicks; testSceneCarryWritesTriggersBackUnchanged), with MIDINoteTriggerCoordinatorTests 7 and EnvelopeBindingAppTests 1: 10 tests, 0 failures, 33.5 s wall (.build/scratch/mod-006/T09-test.log).

## Phase 6: Polish & Cross-Cutting

- [X] MOD-006-T10 Whole ParameterGraph and SceneFormat suites on the host (each under 1 minute); Linux shape: no Apple-only API or stdio global in the new files; repository checks (`check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`), `check_privacy_manifest.py` on the built Debug app and `scripts/check_network_symbols`. — Verified 2026-11-14: ParameterGraph 150 tests (107 + 43, 1 skipped), 1.9 s wall; SceneFormat 144 tests, 8.4 s wall; no Foundation, Darwin or stdio use in ThresholdTrigger.swift or SceneTriggers.swift (Linux itself runs only in CI); check_compliance, validate_docs (1296 files), check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 tests OK (1 skipped); check_privacy_manifest OK and check_network_symbols OK (19 images) on the Debug simulator app.
- [X] MOD-006-T11 Docs: the scene-document contract (`specs/059-scn-001-versioned-scene-format/contracts/scene-document.md`) gains the `triggers` row; spec Status Implemented; PosterBoard count again; delete the simulator and derived data. — Verified 2026-11-14: scene-document contract gains the Triggers section, validate_docs OK; spec Status Implemented; PosterBoard reports 25 before and after; simulator "MOD6 iPhone 17" and the derived data deleted at the end.

## Dependencies

T01 → T02 → T03 → T04 → T05 → T07 → T08 → T09; T06 can be written alongside T04-T05 (red until T07); T10, T11 last.

## Parallel examples

- T06 (SceneFormat tests) alongside T04 (ParameterGraph tests): different packages.

## Implementation strategy

MVP is User Story 1 (T01-T03): the pure trigger and the acceptance proof. Then robustness (T04), the
bank, scenes and app (T05-T09), polish (T10, T11).
