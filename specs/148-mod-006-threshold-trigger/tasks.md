# Tasks: MOD-006 Threshold Trigger

**Input**: Design documents in `specs/148-mod-006-threshold-trigger/` (spec.md, plan.md, research.md,
data-model.md, contracts/threshold-trigger.md, quickstart.md).

**Tests**: test-first (the spec's acceptance is a test); the red run (compile failure) is recorded
before the production change. Budgets (owner rule 7): each unit test ≲ 1-2 s, each suite under
1 minute. Logs go to `.build/scratch/mod-006/`.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. Inside descriptions "T03" is short for
`MOD-006-T03`. A task is ticked only with its evidence, " — Verified <date>: <how>" appended.

## Phase 1: Setup

- [ ] MOD-006-T01 Record the baseline: `swift test --package-path Packages/ParameterGraph` and `swift test --package-path Packages/SceneFormat` on the host (counts, failures); count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`.

## Phase 2: Foundational

None: the pure trigger (contract T1, T2) is User Story 1's deliverable and every later story builds on it.

## Phase 3: User Story 1 - noise near the threshold fires once, not a storm (P1) MVP

**Independent test**: `ThresholdTriggerTests.testNoiseAroundThresholdProducesNoTriggerStorm`, `testCleanPulseTrainFiresOncePerPulse`.

- [ ] MOD-006-T02 [US1] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/ThresholdTriggerTests.swift`: (a) acceptance: settings high 0.6, low 0.4 (width 0.2); seeded SplitMix64 noise of amplitude ±0.19 (below the width) for 10 s at 60 fps (600 frames) centred on 0.6, on 0.4 and on 0.5, also with interval 0 and hold 0 — at most 1 trigger in each case (`XCTAssertLessThanOrEqual(count, 1)`); (b) a clean pulse train (0.9 for 50 ms, 0.1 for 250 ms, 10 pulses) at 60 fps fires exactly 10 times, each on the first frame above high.
- [ ] MOD-006-T03 [US1] Record T02's red run; implement `Packages/ParameterGraph/Sources/ParameterGraph/ThresholdTrigger.swift`: `ThresholdTriggerSettings` ("`low` and `high` finite within 0…1 with `low < high`; interval and hold finite within 0…60 s", defaults interval 0.1 s, hold 0), `validationProblem`, `ThresholdTriggerError`, `ThresholdTrigger` with `step(value:timeNanoseconds:) -> Bool` per data-model.md transitions. Evidence: T02 passes.

## Phase 4: User Story 2 - frame-rate independent and robust (P1)

**Independent test**: `ThresholdTriggerTests.testMinimumIntervalAt60And120FpsAndJitter`, `testEdgeInputs`.

- [ ] MOD-006-T04 [US2] Add to `ThresholdTriggerTests.swift`: pulses every 80 ms with interval 100 ms at 60 fps, 120 fps and seeded jitter (4–40 ms frames): every gap between fires ≥ 100 ms, and with pulses every 300 ms the count is equal at all three rates; hold 50 ms: a 30 ms excursion does not fire, a 70 ms one fires once; equality edges (v == high does not fire, v == low does not re-arm); NaN and ±∞ neither fire nor re-arm and restart a hold; repeated and backwards times count as no elapsed time; invalid settings (low ≥ high, NaN, 1.5, interval −1 or 61) refused; two jitter runs give identical fire times. Evidence: passes after T03.

## Phase 5: User Story 3 - scenes keep triggers and they drive the show (P2)

**Independent test**: `ThresholdTriggerBankTests` (in `ThresholdTriggerTests.swift`), `SceneTriggerTests`, `ThresholdTriggerAppTests`.

- [ ] MOD-006-T05 [US3] Add bank tests to `ThresholdTriggerTests.swift` (kick and band sources through `AudioFeatureFrame`, fire order, at most 8, invalid set leaves the bank unchanged); implement `ThresholdTriggerAction` (`cue.next`, `cue.previous`, `blackout`), `ThresholdTriggerBinding`, `ThresholdTriggerBank` (contract T3) in `ThresholdTrigger.swift`.
- [ ] MOD-006-T06 [P] [US3] Write `Packages/SceneFormat/Tests/SceneFormatTests/SceneTriggerTests.swift`: a scene with two triggers decodes, encodes byte-identically and reads back equal bindings that fire identically; a scene without `triggers` encodes without the field; issues (contract T5): `low ≥ high` → `invalidTrigger` at `$.triggers[0]`; unknown action → `unknownTrigger` at `$.triggers[1].action`; unknown source → at `.source`; missing `high` → `invalidTrigger` at `.high`; 9 entries → the ninth reported; all warnings, the scene loads (`liveState`) and `init(live:)` writes the list back unchanged; a non-object entry is a decode error. Record the red run.
- [ ] MOD-006-T07 [US3] Implement `Packages/SceneFormat/Sources/SceneFormat/SceneTriggers.swift` (`SceneTriggerEntry`, `read`, `SceneLimits.maximumTriggers`), the `triggers` field in `SceneDocument.swift`, decoding (`SceneDecoding.swift`, known keys), encoding only when non-nil (`SceneEncoding.swift`), issue codes `invalidTrigger`, `unknownTrigger` as warnings (`SceneIssue.swift`), `validate` including them (`SceneValidation.swift`), `SceneLiveState.triggers` carried by `liveState` and `init(live:)` (`SceneLiveState.swift`). Evidence: T06 and the whole SceneFormat suite (QA-004 meta-test, legacy fixtures) pass.
- [ ] MOD-006-T08 [US3] App: `MIDINoteActionPerformer.fire(_:)` (`Apps/projectM-iOS/Coordinators/MIDINoteActionPerformer.swift`); `NativeSpectrumHost.setTriggers(_:)`, `onTrigger`, evaluation in `applyModulation` (`Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift`); scene carry `triggers` written back and `triggerBindings` (`SceneAutosaveCapture.swift`, `SceneAutosaveCoordinator.swift`); `Apps/projectM-iOS/Coordinators/AppCoordinator+ThresholdTriggers.swift` connecting them, called from the native visual creation in `AppCoordinator.swift`.
- [ ] MOD-006-T09 [US3] Write `Apps/projectM-iOS/Tests/ThresholdTriggerAppTests.swift`: a kick trigger (high 0.6, low 0.3) on `cue.next` through `NativeSpectrumHost` and a `MIDINoteActionPerformer` with recorded actions; 4 kicks (kick envelope 1 decaying with τ 120 ms, every 500 ms, plus seeded ±0.05 noise) at 60 fps → exactly 4 "next"; skips without Metal; also the carry writes `triggers` back unchanged. Run on "MOD6 iPhone 17" (build-for-testing, test-without-building -only-testing), type-check flags on.

## Phase 6: Polish & Cross-Cutting

- [ ] MOD-006-T10 Whole ParameterGraph and SceneFormat suites on the host (each under 1 minute); Linux shape: no Apple-only API or stdio global in the new files; repository checks (`check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`), `check_privacy_manifest.py` on the built Debug app and `scripts/check_network_symbols`.
- [ ] MOD-006-T11 Docs: the scene-document contract (`specs/059-scn-001-versioned-scene-format/contracts/scene-document.md`) gains the `triggers` row; spec Status Implemented; PosterBoard count again; delete the simulator and derived data.

## Dependencies

T01 → T02 → T03 → T04 → T05 → T07 → T08 → T09; T06 can be written alongside T04-T05 (red until T07); T10, T11 last.

## Parallel examples

- T06 (SceneFormat tests) alongside T04 (ParameterGraph tests): different packages.

## Implementation strategy

MVP is User Story 1 (T01-T03): the pure trigger and the acceptance proof. Then robustness (T04), the
bank, scenes and app (T05-T09), polish (T10, T11).
