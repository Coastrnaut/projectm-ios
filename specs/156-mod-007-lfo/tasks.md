# Tasks: MOD-007 LFO Sine and Triangle

**Input**: Design documents in `specs/156-mod-007-lfo/` (spec.md, plan.md, research.md, data-model.md,
contracts/lfo.md, quickstart.md).

**Tests**: test-first (the spec's acceptance is a test); the red run (compile failure) is recorded
before the production change. Budgets (owner rule 7): each unit test ≲ 1-2 s, each suite under
1 minute. Logs go to `.build/scratch/mod-007/`.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. Inside descriptions "T03" is short for
`MOD-007-T03`. A task is ticked only with its evidence, " — Verified <date>: <how>" appended.

## Phase 1: Setup

- [X] MOD-007-T01 Record the baseline: `swift test --package-path Packages/ParameterGraph` and `swift test --package-path Packages/SceneFormat` on the host (counts, failures); count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`. — Verified 2026-11-14: at a32611cd, ParameterGraph 150 tests on the host (107 + 43, 1 skipped), 0 failures (19.8 s wall incl. build); SceneFormat 144 tests, 0 failures (5.4 s of tests); PosterBoard reports 25 (.build/scratch/mod-007/T01-*.log).

## Phase 2: Foundational

None: the pure oscillator (contract L1, L2) is User Story 1's deliverable and every later story builds on it.

## Phase 3: User Story 1 - known time samples match the waveform (P1) MVP

**Independent test**: `LFOTests.testKnownTimeSamplesMatchClosedForm`, `testLongRunningTimeHasNoDrift`.

- [X] MOD-007-T02 [US1] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/LFOTests.swift`: (a) acceptance: for sine and triangle × representative settings (rate 0.25 / 1 / 2.5 / 0.3 Hz; phase 0 / 0.125 / 0.6; amplitude 1 / 0.4 / 0; center 0.5 / 0.3 / 0.9), sample at t = 0, ¼, ½, ¾ period and at π s and √2 s (integer nanoseconds) and compare with an independent closed form (`center + amplitude/2·w(frac(phase + rate·t))`, clamped to 0…1) within 1e-9; also exact expected values at the quarter points for the full-swing case (0.5, 1, 0.5, 0); (b) long time: 10 h + ¼ period and 3 days + ⅛ s at rates 0.25 and 0.3 Hz, expected phase computed with integer arithmetic (`(3·N) mod 10¹⁰` for 0.3 Hz), within 1e-9. — Verified 2026-11-14: LFOTests.swift written before the production code; red run `cannot find type 'LFOShape' in scope` (.build/scratch/mod-007/red-T02.log).
- [X] MOD-007-T03 [US1] Record T02's red run; implement `Packages/ParameterGraph/Sources/ParameterGraph/LFO.swift`: `LFOShape` (`sine`, `triangle`), `LFO` ("rate 0.01…20 Hz; phase, amplitude, center 0…1, finite", defaults phase 0, amplitude 1, center 0.5), `validationProblem`, `LFOError`, `phase(elapsedNanoseconds:rateHz:)` (seconds/remainder split with fused multiply-add, research MOD-007-D2), `value(elapsedNanoseconds:maximumRateHz:)`. Evidence: T02 passes. — Verified 2026-11-14: testKnownTimeSamplesMatchClosedForm (2 shapes × 5 settings × 7 times = 70 samples, plus the textbook 0.5/1/0.5/0 quarter values and the triangle ⅛ point, all within 1e-9) and testLongRunningTimeHasNoDrift (10 h, 10 h + 0.8 s, 3 days, 7 days against integer-exact phases, within 1e-9) pass; ParameterGraph 160 tests (116 + 44, 1 skipped), 0 failures, 3.3 s wall (.build/scratch/mod-007/T03.log).

## Phase 4: User Story 2 - deterministic, bounded and safe (P1)

**Independent test**: `LFOTests.testDeterministicAcrossFrameRates`, `testOutputBounded`, `testReduceFlashingCapsRate`, `testBankOriginAndSlots`.

- [X] MOD-007-T04 [US2] Add to `LFOTests.swift`: two runs at 60 and 120 fps compared at shared times are bit-identical; extreme settings (center 0.9 amplitude 1; center 0 amplitude 1) stay in 0…1 and clamp; invalid settings (rate 0, 0.005, 21, NaN; phase −0.1, 1.5; amplitude 2; center −1) refused; phase 1 equals phase 0; a 10 Hz oscillator with `maximumRateHz: LFOBank.reduceFlashingMaximumRateHz` equals a 3 Hz oscillator at sampled times and its upward zero crossings in 2 s number 6, not 20; bank: at most 8, invalid set leaves it unchanged, origin at first sample, earlier time reads elapsed 0, nil slot writes 0. Implement `LFOBank` in `LFO.swift` (contract L3). Evidence: passes. — Verified 2026-11-14: testDeterministicAcrossFrameRates (bit-identical at shared times for 120 fps, 60 fps and a 1 ms step), testOutputBoundedAndInvalidSettingsRefused, testReduceFlashingCapsRate (10 Hz: 20 upward crossings in 2 s uncapped, 6 capped; equals a 3 Hz oscillator), testBankOriginSlotsAndLimit pass (.build/scratch/mod-007/T03.log).

## Phase 5: User Story 3 - scenes keep oscillators and they drive bindings (P2)

**Independent test**: `LFOTests.testLFOSourceDrivesBindingThroughModulator`, `SceneLFOTests`, `LFOBindingAppTests`.

- [ ] MOD-007-T05 [US3] Add binding tests to `LFOTests.swift` (`audio.lfo.0`…`audio.lfo.7` parse and round-trip; `audio.lfo.8`, `audio.lfo.01`, `audio.lfo.` do not; `.lfo(i).value(in:)` reads `frame.lfos`, missing → 0, NaN → 0, 1.5 → 1; an `AudioFeatureModulator` binding from `.lfo(0)` to a continuous parameter follows the bank's value; `.lfo(8)` refused with `lfoIndexOutOfRange`; expressions refuse `audio.lfo.0`). Implement `AudioFeatureSource.lfo`, `AudioFeatureFrame.lfos` (default empty), the error case and validation (`AudioFeatureSource.swift`, `AudioFeatureBinding.swift`, `AudioFeatureModulator.swift`), the expression catalog guard and compiler case (`ExpressionCatalog.swift`, `ExpressionCompiler.swift`), the inspector name ("LFO 1", `Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift`).
- [ ] MOD-007-T06 [P] [US3] Write `Packages/SceneFormat/Tests/SceneFormatTests/SceneLFOTests.swift`: a scene with two oscillators (one with an unknown field) decodes, encodes byte-identically and reads back equal oscillators; a binding `audio.lfo.1 → parameter` survives the round trip; a scene without `lfos` encodes without the field; issues (contract L6): rate 25 → `invalidLFO` at `$.lfos[0]`; unknown shape → `unknownLFO` at `$.lfos[1].shape`; missing `rate` → `invalidLFO` at `.rate`; 9 entries → the ninth reported; positions kept (nil for unusable); all warnings, the scene loads (`liveState`) and `init(live:)` writes the list back unchanged; a non-object entry is a decode error. Record the red run.
- [ ] MOD-007-T07 [US3] Implement `Packages/SceneFormat/Sources/SceneFormat/SceneLFOs.swift` (`SceneLFOEntry`, `read`, `SceneLimits.maximumLFOs` = 8, `maximumLFOEntries` = 64, `SceneDocument.lfoOscillators`), the `lfos` field in `SceneDocument.swift`, decoding (`SceneDecoding.swift`, known keys, entry limit), encoding only when non-nil (`SceneEncoding.swift`), issue codes `invalidLFO`, `unknownLFO` as warnings (`SceneIssue.swift`), repair mapping (`SceneRepair.swift`), `validate` including them (`SceneValidation.swift`), `SceneLiveState.lfos` carried by `liveState` and `init(live:)` (`SceneLiveState.swift`); add the file to `SceneSourceSafetyTests` if it lists files. Evidence: T06 and the whole SceneFormat suite (QA-004 meta-test, legacy fixtures) pass.
- [ ] MOD-007-T08 [US3] App: `NativeSpectrumHost.setLFOs(_:)`, `lfos`, an 8-slot scratch filled in `applyModulation` (cap while `reduceFlashing`) and passed as `frame.lfos` (`Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift`); scene carry `lfos` written back and `lfoOscillators` (`SceneAutosaveCapture.swift`, `SceneAutosaveCoordinator.swift`); `Apps/projectM-iOS/Coordinators/AppCoordinator+LFOs.swift` called from the native visual creation in `AppCoordinator.swift`.
- [ ] MOD-007-T09 [US3] Write `Apps/projectM-iOS/Tests/LFOBindingAppTests.swift`: a 0.5 Hz sine (amplitude 1, center 0.5) bound to the glow intensity (replace 0…1) through `NativeSpectrumHost`; frames at 60 fps for 2 s; at sampled frames the effective glow intensity equals the binding's mapping of the closed-form value (clamped to the parameter's range) within 1e-6, rising toward ¼ period and falling toward ¾; with `reduceFlashing` a 10 Hz LFO's effective glow equals a 3 Hz one at sampled times; the carry writes `lfos` back unchanged. Skips without Metal. Run on "MOD7 iPhone 17" (build-for-testing, test-without-building -only-testing), type-check flags on.

## Phase 6: Polish & Cross-Cutting

- [ ] MOD-007-T10 Whole ParameterGraph and SceneFormat suites on the host (each under 1 minute); Linux shape: no Apple-only API or stdio global in the new files; repository checks (`check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`), `check_privacy_manifest.py` on the built Debug app and `scripts/check_network_symbols`.
- [ ] MOD-007-T11 Docs: the scene-document contract (`specs/059-scn-001-versioned-scene-format/contracts/scene-document.md`) gains the `lfos` section and the `audio.lfo.<index>` source; spec Status Implemented; PosterBoard count again; delete the simulator and derived data.

## Dependencies

T01 → T02 → T03 → T04 → T05 → T07 → T08 → T09; T06 can be written alongside T04-T05 (red until T07); T10, T11 last.

## Parallel examples

- T06 (SceneFormat tests) alongside T04 (ParameterGraph tests): different packages.

## Implementation strategy

MVP is User Story 1 (T01-T03): the pure oscillator and the acceptance proof. Then determinism and safety
(T04), the binding source, scenes and app (T05-T09), polish (T10, T11).
