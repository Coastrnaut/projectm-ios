# Tasks: SHOW-005 Cue Hold and Skip

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/show-cue-hold-skip.md](contracts/show-cue-hold-skip.md), [quickstart.md](quickstart.md)

**Tests**: requested by the roadmap acceptance and the brief (injected-clock hold tests, skip stepping, round trip,
lock refusal, one short UI test). Budgets (owner rule 7): unit tests ~1-2 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [X] SHOW-005-T01 Create simulator "SHOW5 iPhone 17" (iOS 27.2), fetch the presets, run `xcodegen generate` in the worktree, and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any simulator run — Verified 2026-11-14: simulator "SHOW5 iPhone 17" created, presets fetched, `xcodegen generate`; PosterBoard reports 26 before

## Phase 2: Foundational (model and file; blocks every story)

- [X] SHOW-005-T02 In `Packages/ShowControl/Sources/ShowControl/ShowCueList.swift`: `ShowCue.skipped: Bool` ("default false"), `ShowStepOutcome.allSkipped`, skip-aware `next()`, `previous()`, `canGoNext`, `canGoPrevious` (nearest cue not skipped; `.allSkipped` when every cue is skipped), `go(to:)` unchanged, `setSkipped(_:_:)` (never moves the position), `insert(…, skipped:)` — Verified 2026-11-14: ShowSkipTests (6) in `swift test --package-path Packages/ShowControl`, 120 tests, 0 failures, 1.8 s
- [X] SHOW-005-T03 In `Packages/ShowControl/Sources/ShowControl/ShowDocument.swift`: optional per-cue `skip` ("`true` written only when skipped; absent/null/false = not skipped; any other JSON type dropped") via a lenient `StoredSkip`, warning `droppedSkipFlags(Int)`, no version bump (contract K1-K2) — Verified 2026-11-14: ShowSkipTests testSkipFlagRoundTripsAndOnlySkippedCuesWriteIt and testInvalidSkipValuesAreDroppedAndCounted
- [X] SHOW-005-T04 In `Packages/ShowControl/Sources/ShowControl/ShowAdvanceTimeline.swift`: `rearm(cueID:remaining:at:)` (held when the timeline is held, else running at now + remaining) — Verified 2026-11-14: ShowControl suite (120 tests) builds and passes; behavior covered by CueHoldSkipAcceptanceTests (T09)

## Phase 3: User Story 1 — Hold the timed show (P1, MVP)

**Independent test**: `ShowManualClock`; 30 s dwell; Hold at 18 s; no advance at the deadline or 10 min later; one manual Next moves one cue; Hold off → advance exactly 12 s later.

- [X] SHOW-005-T05 [US1] `Apps/projectM-iOS/Coordinators/ShowAutoAdvanceCoordinator.swift`: session-only `isOperatorHeld`, `setOperatorHold(_:)` (effective hold = operator hold OR `isHeld()`, applied at once); withdraw a waiting **timed** quantized step and `rearm` at 0 (contract H4); `listChanged` also cancels when the active cue has no next cue (K4) — Verified 2026-11-14: CueHoldSkipAcceptanceTests (7 tests, 0.09 s) on "SHOW5 iPhone 17"; ShowAutoAdvanceCoordinatorTests 5, ShowCueQuantizerAcceptanceTests 8 still pass
- [X] SHOW-005-T06 [US1] `Apps/projectM-iOS/Coordinators/ShowCueQuantizer.swift`: `withdrawTimed() -> Bool` (cancels only a waiting timed step, reschedules, no announcement) — Verified 2026-11-14: CueHoldSkipAcceptanceTests testHoldWithdrawsATimedStepWaitingForTheBeat
- [X] SHOW-005-T07 [US1] `Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift`: `toggleShowHold()` / `setShowHold(_:)` announcing "Hold on, timed advances paused" / "Hold off" on the cue lane — Verified 2026-11-14: build-for-testing succeeds; Hold toggled from the cue row in CueHoldSkipUITests (the announcement goes through `announcer.announce(_, kind: .cue)`; check_status_events OK)
- [X] SHOW-005-T08 [US1] `Apps/projectM-iOS/Views/ShowControls.swift`: Hold toggle button in `ShowCueRow` (identifier `showHold`, label "Hold timed advances", value On/Off, toggle trait); `Apps/projectM-iOS/Views/PerformancePad.swift`: "Hold" in the cue readout, VoiceOver ", hold on" and a "Hold"/"Release Hold" action — Verified 2026-11-14: CueHoldSkipUITests testHoldTogglesAndSkipMarksACue (12.8 s): the `showHold` value goes Off → On → Off and Next moves while held; the pad readout and its action build (not driven by a UI test)
- [X] SHOW-005-T09 [US1] Acceptance tests in `Apps/projectM-iOS/Tests/CueHoldSkipAcceptanceTests.swift` (contract H1-H5): hold blocks the advance at and after the deadline, manual Next moves exactly one non-skipped cue, release resumes with the kept time, a waiting timed quantized step is withdrawn and re-requested — Verified 2026-11-14: CueHoldSkipAcceptanceTests (7 tests, 0.09 s) on "SHOW5 iPhone 17": testHoldPreventsAutomaticAdvancesWhileManualNextRemainsAvailable, testReleasingHoldResumesWithTheKeptRemainingTime, testHoldCombinesWithTheOtherHoldSources, testHoldWithdrawsATimedStepWaitingForTheBeat

## Phase 4: User Story 2 — Skip a cue without deleting it (P1)

**Independent test**: next/previous/timed over one and several skipped cues, Go to a skipped cue, all skipped, round trip, lock refusal.

- [X] SHOW-005-T10 [US2] `Apps/projectM-iOS/Coordinators/ShowCoordinator.swift`: `setSkipped` (refused while locked, saves, applies nothing), "All cues are skipped." notice on `.allSkipped`, Duplicate Scene copies the flag, `statusText` "… · all skipped" — Verified 2026-11-14: CueHoldSkipAcceptanceTests (7 tests, 0.09 s) on "SHOW5 iPhone 17"; CueTransitionOverrideAcceptanceTests 2, ShowSceneEditCoordinatorTests 3 still pass
- [X] SHOW-005-T11 [P] [US2] Package tests `Packages/ShowControl/Tests/ShowControlTests/ShowSkipTests.swift`: stepping over one and several skipped cues, Go to a skipped cue, skipping the active cue keeps the position, all skipped, `canGo*`, round trip (byte-identical; no `skip` key without skipped cues), lenient read, timeline over skipped cues via `ShowTimedAdvance.tick` — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` (120 tests, 0 failures, 1.8 s)
- [X] SHOW-005-T12 [US2] App tests in `Apps/projectM-iOS/Tests/CueHoldSkipAcceptanceTests.swift`: timed advance over skipped cues, Skip edit refused while locked (Hold still allowed), countdown cancelled when the last next cue is skipped, all-skipped notice, Duplicate Scene copies the flag (R9) — Verified 2026-11-14: CueHoldSkipAcceptanceTests (7 tests, 0.09 s) on "SHOW5 iPhone 17": testTimedAdvancePassesOverSkippedCuesAndASkipEditCancelsAnOrphanedCountdown, testLockRefusesSkipEditsButNotHoldAndDuplicateKeepsTheFlag, testAllSkippedDoesNotMoveAndPostsANotice
- [X] SHOW-005-T13 [US2] `Apps/projectM-iOS/Views/ShowEditorView.swift`: dimmed row with "Skipped" (VoiceOver ", skipped"), context menu "Skip Cue"/"Don't Skip Cue", trailing swipe "Skip"/"Unskip" next to Delete (identifier `showCueSkip`; research D8), VoiceOver action; hidden while locked — Verified 2026-11-14: CueHoldSkipUITests reads ", skipped" from cue 3 after the trailing Skip swipe; SceneLockUITests (13.9 s) still sees no Delete while locked
- [X] SHOW-005-T14 [US2] UI test `Apps/projectM-iOS/UITests/CueHoldSkipUITests.swift` (< 30 s): the Hold button's value toggles; the trailing Skip swipe makes cue 3 read ", skipped" — Verified 2026-11-14: CueHoldSkipUITests testHoldTogglesAndSkipMarksACue passed (12.8 s)

## Phase 5: Polish

- [X] SHOW-005-T15 Type-check budget build (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`): no warnings in touched files — Verified 2026-11-14: build-for-testing with -warn-long-function-bodies=300 / -warn-long-expression-type-checking=150: no warnings in touched files
- [X] SHOW-005-T16 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app; spec status; PosterBoard count after; delete the simulator and derived data — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 174 OK; check_privacy_manifest and check_network_symbols OK on the Debug app; PosterBoard 26 before and after

## Dependencies

T01 → T02 → T03, T04 → (T05, T06 → T07 → T08 → T09) and (T10 → T12, T13 → T14); T11 [P] after T03 → T15 → T16.
US1 and US2 share only the foundational phase. MVP: Phase 1-3.
