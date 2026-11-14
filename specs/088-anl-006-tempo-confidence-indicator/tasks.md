# Tasks: ANL-006 Tempo Confidence Indicator

**Input**: Design documents in `specs/088-anl-006-tempo-confidence-indicator/` (spec.md, plan.md,
research.md, data-model.md, contracts/tempo-confidence.md, quickstart.md).

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure)
is recorded before the production change. Budgets (owner rule 7): a unit test about 1-2 s (≤ 10 s),
each package suite under 1 minute, a UI test under 30 s; representative cases only.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel.
`{sim}` = needs the row's own iOS 27.2 simulator "ANL6 iPhone 17" (created for this row, deleted
afterwards). Inside descriptions "T03" is short for `ANL-006-T03`. A task is ticked only when its
evidence was produced, with " — Verified <date>: <how>" appended. Logs go to `.build/scratch/`.

## Phase 1: Setup

- [X] ANL-006-T01 Record the baseline: `swift test --package-path Packages/PerformanceControl` on the host; the five scripts (`check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`); the PosterBoard report count. — Verified 2026-11-13: at e13af72, PerformanceControl 89 tests, 0 failures (1.45 s); check_compliance, validate_docs, check_motion_policy, check_permission_catalog OK; test_scripts.py 147 tests OK (1 skipped); PosterBoard reports 25 (.build/scratch/anl006-T01-*.log).

## Phase 2: Foundational - the indicator (blocks every story)

- [X] ANL-006-T02 Write `Packages/PerformanceControl/Tests/PerformanceControlTests/TempoConfidenceIndicatorTests.swift` against contract C1 on an injected clock: starts searching; first usable estimate → uncertain; ≥ 0.7 at one BPM for 2.0 s → stable (not at 1.75 s); confidence between 0.5 and 0.7 holds stable and never enters it; a dip below 0.5 shorter than 1.0 s stays stable, ≥ 1.0 s → uncertain; BPM beyond 3 % of the locked BPM for 1.0 s → searching (no BPM), then uncertain after 3.0 s if still not stable; a BPM wandering beyond 3 % while uncertain restarts the dwell; nil, NaN, out-of-range BPM → searching; confidence clamped; backwards time adds no elapsed time; `reset()`; the `TempoReadout` mapping (manual wins; stable/uncertain/searching). (US1, US3) — Verified 2026-11-13: 14 tests written before the indicator; red run `cannot find type 'TempoConfidenceIndicator' in scope` (.build/scratch/anl006-red-T02.log).
- [X] ANL-006-T03 Record the T02 red run; implement `Packages/PerformanceControl/Sources/PerformanceControl/TempoConfidenceIndicator.swift` (`TempoConfidenceState`, `TempoConfidenceRules.standard` = enter 0.7, exit 0.5, enter dwell 2 s, exit dwell 1 s, reacquire 3 s, tolerance 0.03, 60…200 BPM with "enterConfidence > exitConfidence" preconditions, `TempoConfidenceIndicator`, `TempoReadout`; research ANL-006-D3). Evidence: T02 passes on the host and with `-Xswiftc -DANALYSIS_NO_ACCELERATE`. — Verified 2026-11-13: TempoConfidenceIndicatorTests 16 (with T05's 2) pass on the host (0.002 s) and in the Linux shape (0.002 s).

## Phase 3: User Story 2 - noise never claims a confident tempo (P1, roadmap acceptance)

**Independent test**: `TempoConfidenceAcceptanceTests`.

- [X] ANL-006-T04 [US2] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/TempoConfidenceAcceptanceTests.swift`: synthetic stereo PCM through `NormalizedPCMRing`'s analysis tap, a real `AnalysisPipeline` stepped synchronously, `TempoSubscriptionReader`, `TempoSource` and the indicator updated every 250 ms of audio on the sample clock (research ANL-006-D6). Cases: white noise seeds 1-2 and pink noise seeds 4-5 (10 s, peak 0.5), 10 s of silence, and random noise bursts seeds 6-8 (12 s) never reach stable, the largest confidence is < 0.7 and the snapshot is never `.estimated` (print the maximum per input); 120 and 90 BPM pulses reach stable at ±1 BPM within 10 s and stay stable; 12 s at 120 then 14 s at 90 leaves stable and is stable at 90 within 12 s of the change (ANL-006-S1 to S3). Evidence: passes on the host and in the Linux shape; each test ≤ 10 s; whole suite < 1 minute. — Verified 2026-11-13: 5 tests pass on the host (2.35, 1.52, 0.54, 0.60, 1.17 s) and in the Linux shape `-Xswiftc -DANALYSIS_NO_ACCELERATE` (5.32, 5.11, 1.63, 2.21, 2.45 s). Largest confidence: white 1, 2 and pink 4, 5 and silence 0.0 (no estimate, always searching); bursts 6: 0.290, 7: 0.292, 8: 0.373 (searching/uncertain, never stable); never an estimated snapshot. 120 BPM stable at 5.29 s, 90 BPM at 6.27 s (confidence 1.0); 120 → 90 left stable 3.79 s after the change (searching, then uncertain), stable at 90 after 7.78 s. Whole suite: 110 tests, 0 failures, 7.6 s on the host and 22.4 s in the Linux shape (first split version; .build/scratch/anl006-T04-*.log). Implementation finding: stationary noise gives no estimate, so noise bursts were added (spec Clarifications).

## Phase 4: User Story 3 - no flicker (P2)

- [X] ANL-006-T05 [US3] Add to `TempoConfidenceIndicatorTests.swift`: a seeded random confidence uniform in 0.45…0.75 at 120 BPM, 4 Hz for 60 s, changes state at most twice (`stateChanges`); confidence alternating 0.45/0.75 every poll after stable stays stable (ANL-006-S4). Evidence: passes on the host. — Verified 2026-11-13: both pass on the host and in the Linux shape; the borderline run stays within 2 changes (asserted) and the alternating run keeps exactly the 2 changes of reaching stable.

## Phase 5: User Story 1 - the readout shows the state (P1)

**Independent test**: `TempoCoordinatorTests`, `TempoConfidenceUITests`.

- [X] ANL-006-T06 [US1] Update `Apps/projectM-iOS/Tests/TempoCoordinatorTests.swift`: an injected `stateClock`; the readout text, word and accessibility value for manual, stable, uncertain and searching (contract C1 app table); Reset returns to the analysis's current state without a new dwell; the Reset announcement per state; stopping the analysis returns to searching; the Tap value uses the new words. — Verified 2026-11-13: TempoCoordinatorTests 9 tests (3 new: texts per state, readout follows the indicator, DEBUG script) pass on the iOS 27.2 simulator "ANL6 iPhone 17"; first run caught a wrong test input (0.6 is above the snapshot's 0.5 floor; changed to 0.45) (.build/scratch/anl006-unit.log, anl006-test2.log).
- [X] ANL-006-T07 [US1] Implement in `Apps/projectM-iOS/Coordinators/TempoCoordinator.swift` (indicator, `stateClock`, `readout`, text functions on `TempoReadout`, announcement, reset on stop, DEBUG estimate override) and `Apps/projectM-iOS/Views/TempoControls.swift` (two lines and accessibility value from `TempoReadout`, strings built in typed steps; no opacity or secondary-style dimming of the number line, ANL-006-R9); the DEBUG launch argument `-uitestTempoEstimate` in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`. Evidence: T06 passes `{sim}`; projectM-iOSTests all pass. — Verified 2026-11-13: app builds for the simulator with no warnings in the touched files; projectM-iOSTests 398 tests, 0 failures (10.3 s) (.build/scratch/anl006-test4.log).
- [X] ANL-006-T08 [US1] Write `Apps/projectM-iOS/UITests/TempoConfidenceUITests.swift` (`-uitestTempoEstimate 120:0.9:40:0.3`: the readout reaches "120 BPM, stable", then "About 120 BPM, uncertain") and update `Apps/projectM-iOS/UITests/TapTempoUITests.swift`'s post-reset expectation for the new words. Evidence: passes in < 30 s `{sim}` with TapTempoUITests, AccessibilityScreensUITests and NativeVisualUITests green. — Verified 2026-11-13: TempoConfidenceUITests passes in 15.5 s (17.6 s on its first green run; the first version read the readout while the controls auto-hid and failed, so it launches with ACC-004's `-uitestKeepControls`); TapTempoUITests 7.2 s; AccessibilityScreensUITests 7 tests (8.5-20.6 s each, the readout's new "Searching" word passes the controls audit); NativeVisualUITests 4 (9.2-17.9 s); 13 UI tests, 0 failures (.build/scratch/anl006-test4.log).

## Phase 6: Polish

- [X] ANL-006-T09 Add a note to `specs/027-show-011-tap-tempo/contracts/tempo-source.md` (readout words and the Tap value now follow ANL-006; the snapshot is unchanged); run the five scripts; count PosterBoard reports; delete the row's simulator; mark the spec Implemented. — Verified 2026-11-13: SHOW-011 contract note added; ACC-004's em-dash filter reason and contract row now say "Searching for tempo"; check_compliance, validate_docs, check_motion_policy, check_permission_catalog OK; test_scripts.py 147 OK (1 skipped); PosterBoard reports 25 before and after; simulator "ANL6 iPhone 17" deleted.

## Dependencies

T01 → T02 → T03 → (T04, T05 in parallel) ; T03 → T06 → T07 → T08 → T09.

## Parallel example

After T03: T04 (package acceptance, host CPU) and T06 (app test edits, no build) can be written in
parallel; the app build waits for T07.

## Implementation strategy

MVP = T01-T04 (the roadmap acceptance in the package); then the readout (T06-T08); polish last.

## Analysis (speckit-analyze, 2026-11-13)

Coverage: R1-R6 → T02-T05; R7, R8, R12 → T06-T07; R9 → T07 (no dimming) and T08 (AccessibilityScreensUITests);
R10 → T03 (TempoSource untouched; existing TempoSource tests in T01/T04 runs); R11 → T09
(check_motion_policy). S1-S3 → T04; S4 → T05; S5 → T06, T08; S6 → T04, T07, T08. Findings applied:
(1) S5 promised the UI test would see the searching phase, which happens before the controls can be
read; S5 now asks for stable then uncertain, and the earlier phases are unit-tested. (2) R9 had no
task wording; T07 now says no dimming. No constitution conflict, no duplicate or orphan task.
