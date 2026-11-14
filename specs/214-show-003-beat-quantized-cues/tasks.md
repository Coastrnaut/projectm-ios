# Tasks: SHOW-003 Beat-Quantized Cue Advance

**Input**: Design documents from `specs/214-show-003-beat-quantized-cues/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cue-step-quantizer.md, quickstart.md

Tests are requested by the roadmap acceptance ("Synthetic beats trigger once and missing tempo uses explicit fallback").

## Phase 1: Setup

- [X] SHOW-003-T01 Create the private simulator "SHOW3 iPhone 17" (iOS 27.2) and count PosterBoard reports before any run — Verified 2026-11-14: simulator 4240079C created on iOS 27.2; PosterBoard reports 26 before

## Phase 2: Foundational

- [X] SHOW-003-T02 Add `CueStepRequest`, `CueStepRequestResult` and `QuantizedCueStep` (contract Q1; reuses `QuantizeMode`, `QuantizeImmediateReason`, `TempoSnapshot.nextBoundary(after:beats:)`; "at most one step is queued"; Cue mode stored as Off) in Packages/PerformanceControl/Sources/PerformanceControl/QuantizedCueStep.swift — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl` (257 tests pass, 14.1 s)
- [X] SHOW-003-T03 Add `ShowStepOutcome.queued` (documented as returned only by the app's quantized gate) in Packages/ShowControl/Sources/ShowControl/ShowCueList.swift — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` (110 tests pass, 1.4 s)

## Phase 3: User Story 1 - Next cue on the beat (P1) MVP

**Independent test**: synthetic 120 BPM grid, injected times; a mid-beat Next moves 0 times before, exactly once at, and 0 times over 3 further beats.

- [X] SHOW-003-T04 [US1] Package tests (Beat once-only over 3 further beats, Bar ignores inner beats, request exactly on a beat waits, same request cancels, different replaces with a new deadline, timed keeps a pending manual request, clock jump returns once, setMode drops, a later tempo does not move a computed deadline) in Packages/PerformanceControl/Tests/PerformanceControlTests/QuantizedCueStepTests.swift — Verified 2026-11-14: `swift test --filter QuantizedCueStepTests` (9 tests, 0.001 s), acceptance `testNextMidBeatTriggersExactlyOnceAtTheNextBeat`
- [X] SHOW-003-T05 [US1] `ShowCueQuantizer` (mode under `settings.show.quantizeCues`, absent = Off; request, tick(at:), wake-up task, `willStep`, announcements, `queuedText`, `appliedAtBoundary`) in Apps/projectM-iOS/Coordinators/ShowCueQuantizer.swift; `AppSettings.showCueQuantizer` and `allKeys` in Apps/projectM-iOS/Coordinators/AppSettings.swift — Verified 2026-11-14: app tests on "SHOW3 iPhone 17" (iOS 27.2): `ShowCueQuantizerAcceptanceTests` (8 tests, 0.10 s); build-for-testing with the type-check flags shows no long bodies or expressions
- [X] SHOW-003-T06 [US1] Gate in `ShowCoordinator.next/previous/go(to:)`, `stepNow(_:)` and `timedNext()` in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift; wiring (tempo snapshot, monotonic clock, `.cue` lane, MOD-017 `tick` first) in Apps/projectM-iOS/Coordinators/AppCoordinator+ParameterQuantizer.swift — Verified 2026-11-14: app tests on "SHOW3 iPhone 17" (iOS 27.2): `ShowCueQuantizerAcceptanceTests`, `ShowCoordinatorTests`, `ParameterQuantizerAcceptanceTests` pass
- [X] SHOW-003-T07 [US1] App acceptance over a real show and store (Next mid-beat once at the beat and never again; Bar waits for the bar; Previous replaces Next; Next twice cancels; Next at the last cue is not queued; a queued Go to a removed cue does nothing; a mode change cancels with "Queued cue cancelled"; a MOD-017 Beat change due at the same beat applies before the cue and a Cue-mode change still lands on the queued cue's scene) in Apps/projectM-iOS/Tests/ShowCueQuantizerAcceptanceTests.swift — Verified 2026-11-14: app tests on "SHOW3 iPhone 17" (iOS 27.2): `testNextMidBeatMovesExactlyOnceAtTheNextBeat`, `testBarWaitsForTheBarAndLatestRequestWins`, `testTheSameRequestAgainCancelsAndANonMovingStepIsNotQueued`, `testRemovedGoTargetDoesNothingAndModeChangeCancels`, `testSameBeatParameterChangeAppliesFirstAndCueModeChangeLandsOnTheQueuedCue`

## Phase 4: User Story 2 - No tempo: explicit fallback (P1)

- [X] SHOW-003-T08 [US2] Package and app tests: no tempo / no phase → `.applyNow(.noTempo)`, the show moves at once and "Cue changed now, no tempo" is announced (Packages/PerformanceControl/Tests/PerformanceControlTests/QuantizedCueStepTests.swift, Apps/projectM-iOS/Tests/ShowCueQuantizerAcceptanceTests.swift) — Verified 2026-11-14: `testNoTempoOrNoPhaseAppliesNow` (package) and `testNoTempoMovesAtOnceWithTheFallbackAnnouncement` (app tests on "SHOW3 iPhone 17" (iOS 27.2))

## Phase 5: User Story 3 - Know what is waiting (P2)

- [X] SHOW-003-T09 [US3] "Quantize cue steps" picker (Off/Beat/Bar) as a new section in Apps/projectM-iOS/Views/QuantizeCueStepsSection.swift, added to a section property of Apps/projectM-iOS/Views/SettingsView.swift; queued text in Apps/projectM-iOS/Views/ShowControls.swift and Apps/projectM-iOS/Views/PerformancePad.swift — Verified 2026-11-14: UI test `QuantizedCueStepsUITests` finds the picker with Beat chosen; build-for-testing succeeded
- [X] SHOW-003-T10 [US3] SHOW-002 timed advance uses `timedNext()` in Apps/projectM-iOS/Coordinators/ShowAutoAdvanceCoordinator.swift; app test: a due timed advance moves once at the next beat (Apps/projectM-iOS/Tests/ShowCueQuantizerAcceptanceTests.swift) — Verified 2026-11-14: app tests on "SHOW3 iPhone 17" (iOS 27.2): `testTimedAdvanceMovesOnceAtTheNextBeat`; `ShowAutoAdvanceCoordinatorTests` (5) pass
- [X] SHOW-003-T11 [US3] UI test (Settings offers the picker; with Beat and no tempo Next still moves the show) in Apps/projectM-iOS/UITests/QuantizedCueStepsUITests.swift, under 30 s — Verified 2026-11-14: `QuantizedCueStepsUITests` passes on "SHOW3 iPhone 17" in 8.2 s

## Phase 6: Polish

- [X] SHOW-003-T12 New key in `ALLOWED_KEYS` (scripts/run_device_tests.py), FILE-005 `excludedKeys` (Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift), FILE-011 erase list (Packages/LibraryBackup/Sources/LibraryBackup/LibraryErasePolicy.swift); run `LibraryBackupAppTests` and the LibraryBackup package tests — Verified 2026-11-14: app tests on "SHOW3 iPhone 17" (iOS 27.2): `LibraryBackupAppTests` (5) and `testModeIsStoredAndListedForResetAndBackupPolicy`; `swift test --package-path Packages/LibraryBackup` (77 pass, 9.7 s)
- [X] SHOW-003-T13 Regression: `ShowCoordinatorTests`, `ShowAutoAdvanceCoordinatorTests`, `ParameterQuantizerAcceptanceTests`, ShowControl package tests; type-check budget flags on the touched files — Verified 2026-11-14: app tests on "SHOW3 iPhone 17" (iOS 27.2): 36 unit tests in 0.41 s (ShowCueQuantizerAcceptance 8, ShowCoordinator 8, ShowAutoAdvance 5, ParameterQuantizerAcceptance 6, LibraryBackupApp 5, PerformancePad 4); ShowControl and PerformanceControl suites pass
- [X] SHOW-003-T14 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app; PosterBoard count after; delete the simulator and derived data — Verified 2026-11-14: all six repo checks pass (164 script tests), check_privacy_manifest and check_network_symbols OK on the Debug app; PosterBoard 26 after (no new reports)

## Analysis (speckit-analyze, 2026-11-14)

Applied: R7/R8 announcements, the removed-Go-target edge case, the same-beat MOD-017 order (D6) and the bounded wait
(tempo change after a request) had no test; T04 and T07 now name them. Coverage: R1 T05/T09/T12, R2 T04/T06/T07, R3
T04/T07, R4 T06/T07, R5 T08, R6 T10, R7 T05/T09, R8 T04/T07, R9 T02/T05; S1 T04/T07, S2 T08, S3 T04/T07, S4 T10. No
constitution conflict; no ambiguity left.

## Dependencies

T02 → T04, T05; T03 → T06; T05 → T06 → T07, T08, T10; T09 after T05; T11 after T09; T12 after T05.

## Parallel examples

T02 and T03 (different packages); T09 and T12 (different files).

## Implementation strategy

MVP = US1 (T02-T07); then the fallback (US2), then the indication, timed advance and UI test (US3).
