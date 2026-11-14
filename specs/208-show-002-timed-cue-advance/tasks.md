# Tasks: SHOW-002 Timed Cue Advance

**Input**: specs/208-show-002-timed-cue-advance/ (spec, plan, research, data-model, contracts/show-cue-dwell.md, quickstart)
**Tests**: requested by the roadmap row (deterministic timeline tests + simulator).
Format: `- [ ] SHOW-002-Txx [P?] [USn?] description with file path`.

## Phase 1: Setup

- [ ] SHOW-002-T01 Create simulator "SHOW2 iPhone 17" (iOS 27.2), count PosterBoard reports, run `xcodegen generate` in the worktree

## Phase 2: Foundational (the model and the file)

- [ ] SHOW-002-T02 [P] `ShowCueDwell` ("seconds" Int, "1…3600", init throws `ShowDwellError.outOfRange`; `duration`, `presets` 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300, 600, 900, 1200, 1800, 2700, 3600 s; `clockText` m:ss; `spokenText`) in Packages/ShowControl/Sources/ShowControl/ShowCueDwell.swift
- [ ] SHOW-002-T03 `ShowCue.dwell` (nil = Off), `ShowCueList.setDwell(_:to:)` (unknown cue throws), `insert(… dwell:)` in Packages/ShowControl/Sources/ShowControl/ShowCueList.swift
- [ ] SHOW-002-T04 `show.json` cue field `advanceAfter` (written only when set; lenient read; `ShowDecodeWarning.droppedDwells(n)`; no version bump; contract D1-D2) in Packages/ShowControl/Sources/ShowControl/ShowDocument.swift
- [ ] SHOW-002-T05 [P] Document tests (round trip byte-identical, show without dwells unchanged, each invalid value dropped with one warning, QA-004 matrix still passes) in Packages/ShowControl/Tests/ShowControlTests/ShowDwellDocumentTests.swift

## Phase 3: User Story 1 + 2 — the timeline engine and its acceptance (P1) 🎯 MVP

**Goal**: one advance per cue at its deadline with an injected clock; manual steps reset the deadline.
**Independent test**: `swift test --filter ShowAdvanceTimelineTests`.

- [ ] SHOW-002-T06 [US1] `ShowMonotonicClock`, `ShowContinuousClock`, `ShowManualClock`, `ShowAdvanceTimeline` (idle/running/held; `cueStarted`, `setHeld`, `due`, `remaining`, `cancel`) and `ShowTimedAdvance.tick`/`step` in Packages/ShowControl/Sources/ShowControl/ShowAdvanceTimeline.swift
- [ ] SHOW-002-T07 [US1] Acceptance and engine tests: five cues with dwells 10/20/30/40/50 s stepped in 1 s and 0.25 s ticks fire exactly at 10, 30, 60, 100 s (none early, none twice, show ends on cue 5); a 500 s jump fires once; Off and last cue never fire; a manual Next at 4 s moves the deadline to 24 s and 10 s never fires; Previous and Go to restart in full; hold keeps the remaining time; step while held starts held — in Packages/ShowControl/Tests/ShowControlTests/ShowAdvanceTimelineTests.swift

## Phase 4: User Story 3 — the app driver, holds and countdown (P1)

**Goal**: the app advances by itself, holds on pause/blackout/repair/background, and shows the countdown.
**Independent test**: `ShowAutoAdvanceCoordinatorTests` with a manual clock.

- [ ] SHOW-002-T08 [US3] `ShowCoordinator.cueStarted` hook from `perform`, cancel on removal of the active cue, `setDwell` (refused while locked; saves; restarts the active cue), Duplicate Scene keeps the dwell in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift
- [ ] SHOW-002-T09 [US3] `ShowAutoAdvanceCoordinator` (timeline, injected clock, `isHeld` closure, `tick()`, 4 Hz task only while not idle, `countdown`, `countdownText`, `spokenCountdown`) in Apps/projectM-iOS/Coordinators/ShowAutoAdvanceCoordinator.swift; owned and wired (holds: `userPaused`, blackout phase not live, `sceneRepair.pending`, `!appIsActive`; `sceneBecame`, pause and blackout re-evaluate) in Apps/projectM-iOS/Coordinators/AppCoordinator.swift and AppCoordinator+Show.swift
- [ ] SHOW-002-T10 [US3] Countdown in the cue row (`showCueCountdown`, VoiceOver value) in Apps/projectM-iOS/Views/ShowControls.swift and in the performance pad's cue readout in Apps/projectM-iOS/Views/PerformancePad.swift
- [ ] SHOW-002-T11 [US3] App tests: manual clock, three cues with dwells; one advance per due cue through `show.next()` (scene applied), pause and blackout hold the remaining time, a dwell edit refused while locked, Duplicate keeps the dwell, countdown text — in Apps/projectM-iOS/Tests/ShowAutoAdvanceCoordinatorTests.swift

## Phase 5: User Story 4 — set a cue's dwell (P1)

- [ ] SHOW-002-T12 [US4] `CueDwellView` (Off + presets + a stored non-preset value; `cueDwellPicker`, `cueDwellDone`) in Apps/projectM-iOS/Views/CueDwellView.swift; "Advance After…" in the context menu, a leading swipe action (`showCueDwell`) and a VoiceOver action, and the "Advance after m:ss" caption and spoken value in Apps/projectM-iOS/Views/ShowEditorView.swift
- [ ] SHOW-002-T13 [US4] UI test (< 30 s): a seeded show with a 2 s dwell on cue 1; Next shows the countdown and cue 2 becomes active by itself — Apps/projectM-iOS/UITests/ShowAutoAdvanceUITests.swift with the seed option in Apps/projectM-iOS/Debug/UITestShowFixture.swift

## Phase 6: Polish

- [ ] SHOW-002-T14 Type-check budget (no function > 300 ms, no expression > 200 ms) on the touched app files; repo checks (compliance, docs, motion policy, permission catalog, status events, script tests); `LibraryBackupAppTests` still pass (no new key); privacy manifest and network symbols on the built app
- [ ] SHOW-002-T15 Regression: ShowControl package suite; ShowCoordinatorTests, SceneLockAcceptanceTests, CueTransitionAcceptanceTests; ShowCueUITests; PosterBoard count; delete simulator and derived data; status in spec.md

## Dependencies

T02 → T03 → T04/T05; T03 → T06 → T07; T06 + T03 → T08 → T09 → T10/T11; T08 → T12 → T13; all → T14 → T15.
Parallel: T02 with T05's scaffolding; T10 with T11; T12 with T11.

## Implementation strategy

MVP = Phases 2-3 (the pure engine and its acceptance). Then the app driver (Phase 4), the editor (Phase 5), polish.
