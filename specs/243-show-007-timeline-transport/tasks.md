# Tasks: SHOW-007 Timeline Transport

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/show-timeline-transport.md](contracts/show-timeline-transport.md), [quickstart.md](quickstart.md)

Tests are required (roadmap acceptance, owner rule 7 budgets). `{device}` tasks need a person and stay open.

## Phase 1: Setup

- [X] SHOW-007-T01 Create simulator "SHOW7 iPhone 17" (iOS 27.2), run `xcodegen generate`, record the PosterBoard report count before runs (project.yml unchanged) — Verified 2026-11-14: simulator B6E04341 (iOS 27.2) created, `xcodegen generate`, preset submodules initialised; PosterBoard reports 26 before runs

## Phase 2: Foundational (pure model, ShowControl)

- [X] SHOW-007-T02 Add `ShowTimeline` (entries: non-skipped cues in order "up to and including the first without a dwell"; `start`, `span` nil only for an open end; `duration`, `isOpenEnded`, `canLoop`; `locate(_:looping:)` clamps or wraps; `time(ofCue:elapsed:)`; `loopTarget(from:looping:)`), `ShowSeekAction`/`ShowSeekPlan.plan(list:timeline:to:looping:currentRemaining:)` and `ShowScrub` (`begin`, `move(to:)`, `end() -> Duration?`, `cancel`) in Packages/ShowControl/Sources/ShowControl/ShowTimeline.swift — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` (128 tests, 1.7 s; 5 new in ShowTimelineTests)
- [X] SHOW-007-T03 [P] Package tests (skipped excluded, open end, locate/time round trip, end clamp, loop wrap, seek plan none/reposition/apply, scrub coalescing to one commit) in Packages/ShowControl/Tests/ShowControlTests/ShowTimelineTests.swift — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` (128 tests, 1.7 s; 5 new in ShowTimelineTests)

## Phase 3: User Story 1 — Scrub to a point in the show (P1, MVP)

**Independent test**: seek across three cues → one apply; repeat → nothing.

- [ ] SHOW-007-T04 [US1] `ShowCueQuantizer.withdrawAll()` (silent cancel of any waiting step) in Apps/projectM-iOS/Coordinators/ShowCueQuantizer.swift
- [ ] SHOW-007-T05 [US1] `ShowCoordinator.seek(to:)` (withdraw quantized step, one `perform` with a cut transition) and `timedGo(to:)` in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift
- [ ] SHOW-007-T06 [US1] Driver: playhead (`ShowAdvanceTimeline` always running for a timed cue, same holds), `reposition(cueID:remaining:)` in Apps/projectM-iOS/Coordinators/ShowAutoAdvanceCoordinator.swift
- [ ] SHOW-007-T07 [US1] `ShowTransportCoordinator` (timeline, current time, seek, scrub begin/move/end, preview text) in Apps/projectM-iOS/Coordinators/ShowTransportCoordinator.swift; one lazy var in AppCoordinator.swift; wiring in AppCoordinator+Show.swift
- [ ] SHOW-007-T08 [US1] `ShowTimelineRow` (Play/Pause, accessible slider `showTimelineScrub` 5 s step, position text, Loop toggle) in Apps/projectM-iOS/Views/ShowTimelineRow.swift; shown from ShowCueRow in Apps/projectM-iOS/Views/ShowControls.swift
- [ ] SHOW-007-T09 [US1] Acceptance tests (S1: recorder of applies, transitions, announcements, MOD-017 applies, quantized steps; seek across cues, repeat, same-cue reposition, withdrawn quantized step, scrub; the seek's transition is the resolved cut (Reduce flashing widens it); a seek while the scene is locked still applies; no announcement on seek) in Apps/projectM-iOS/Tests/ShowTransportAcceptanceTests.swift

## Phase 4: User Story 2 — Play, pause and loop (P1)

- [ ] SHOW-007-T10 [US2] Loop: `settings.show.loop` key (absent = off) in ShowTransportCoordinator; driver `loops` closure arms the last timeline cue and wraps via `timedGo`, `passes` counter; key added to `AppSettings.allKeys` (Apps/projectM-iOS/Coordinators/AppSettings.swift), `LibrarySettingsPolicy.excludedKeys` (Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift), the excluded set in Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift and `ALLOWED_KEYS` in scripts/run_device_tests.py
- [ ] SHOW-007-T11 [US2] Play/Pause through SHOW-005 Hold; Play at Standby seeks to 0 (ShowTransportCoordinator)
- [ ] SHOW-007-T12 [US2] Acceptance tests (S2 two passes = two wraps, loop off = none; S3 pause 10 min keeps remaining; Play at Standby applies once; key policy) in Apps/projectM-iOS/Tests/ShowTransportAcceptanceTests.swift

## Phase 5: Polish

- [ ] SHOW-007-T13 UI test seed `-uitestShowTimelineSeed` (five cues, 30 s each) in Apps/projectM-iOS/Debug/UITestShowFixture.swift and UI test (adjust slider → "Cue 3 of 5"; Loop toggles) in Apps/projectM-iOS/UITests/ShowTimelineUITests.swift (< 30 s)
- [ ] SHOW-007-T14 Regression: ShowAutoAdvance, CueHoldSkip, ShowCueQuantizer, LibraryBackupApp tests; ShowControl package on host; Linux shape (ShowTimeline.swift is Foundation only; no Apple-only API, no stdio globals)
- [ ] SHOW-007-T15 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), type-check budget, privacy manifest and network symbols on the Debug app
- [ ] SHOW-007-T16 {device} D1: scrub across cues during a running show on the projector; one look change per release; loop runs two passes

## Dependencies

T01 → T02 → T03; T02 → T04-T09 (US1) → T10-T12 (US2, reuses driver and coordinator) → T13-T15. T16 after all.
Parallel: T03 with T04; T08 with T09.

## Implementation strategy

MVP = US1 (seek without duplicates, the roadmap acceptance). US2 adds Play/Pause wording over Hold and Loop.
