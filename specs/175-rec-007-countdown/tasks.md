# Tasks: REC-007 Recording countdown

**Input**: `specs/175-rec-007-countdown/` (spec, plan, research, data-model, contracts/countdown.md, quickstart)
**Tests**: requested by the roadmap acceptance (cancel prevents file creation; completed countdown starts once) and the brief (Off, background, announcements, UI test).

## Phase 1: Setup

- [ ] REC-007-T01 Add `RecordingCountdownLength` (raw values `off`, `3`, `5`, `10`; absent or unknown → `off`), `RecordingCountdownCancel` (user, background, leftVisualizer, visualLost, presentationLost, blackedOut, paused, each with its caption text), the `RecordingCountdownClock`/`RecordingCountdownTimer` protocols and the system clock (`ProcessInfo.systemUptime`, main-actor `Task.sleep`) in Apps/projectM-iOS/Coordinators/RecordingCountdown.swift (research REC-007-D2)

## Phase 2: Foundational

- [ ] REC-007-T02 Add `case countingDown(Int)` to `VideoRecordingCoordinator.State` (explicit `allCases` with `countingDown(1)`), route `toggle()`, split `start()` into `start(afterCountdown:)`, count `writerCreations`, run the context check and background observer for countdowns, `filesInUse` only while recording or finishing, inject the clock (`countdownClock` init parameter, default system) and add Context `countdown` in Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift; update every exhaustive switch on the state (StatusEvents.swift X9d row, ControlsOverlay, VisualizerView indicator condition, ExternalDisplay hold unchanged)

## Phase 3: User Story 1 - Start after a countdown (P1) MVP

**Goal**: Record with 3/5/10 s counts down and starts exactly once.
**Independent test**: manual-clock unit tests.

- [ ] REC-007-T03 [US1] Implement begin, tick (deadlines start + k), completion (generation token, refusal at completion → idle) and the late-tap guards (0.25 s before completion, 0.5 s after the start) in Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator+Countdown.swift (REC-007-R2, R3, R4; research D3, D4, D5)
- [ ] REC-007-T04 [US1] Add `RecordingCountdownSetting` (key `settings.recording.countdown`, removed by `-uitestResetNotice`) in Apps/projectM-iOS/Coordinators/RecordingCountdownSetting.swift, own it in AppCoordinator.swift and pass `countdown` in `videoRecordingContext`; add the key to `ALLOWED_KEYS` (scripts/run_device_tests.py) and `includedKeys` (Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift) (REC-007-R1, R8)
- [ ] REC-007-T05 [US1] Add `RecordingCountdownSection` (rows `recordingCountdown.off|3|5|10`, checkmark, selected trait) in Apps/projectM-iOS/Views/RecordingCountdownSection.swift and wire it under the frame-rate section in SettingsView.swift (`audioSections`) and VisualizerView.swift (REC-007-R9)
- [ ] REC-007-T06 [US1] Add the countdown overlay (number, label "Recording in N", Cancel with `.keyboardShortcut(.cancelAction)`, no animation) in Apps/projectM-iOS/Views/RecordingCountdownView.swift, show it in VisualizerView's status area, and make the Record item read "Cancel countdown" in ControlsOverlay.swift (REC-007-R7)
- [ ] REC-007-T07 [US1] Status rows X9d (first "Recording in N", then "N") and X9e (caption; user or system) in Apps/projectM-iOS/Coordinators/StatusEvents.swift, posted from StatusCaptionView.swift's `recordingStateChanged` (REC-007-R6, R7; contract C2)
- [ ] REC-007-T08 [US1] Acceptance and unit tests in Apps/projectM-iOS/Tests/RecordingCountdownAppTests.swift: completed 3 s countdown → exactly 1 writer creation, a second toggle at 2.99 s and at 3.0 s (before and after the tick) adds no recording and no stop (REC-007-S2); Off starts in the same call (S3); setting persistence and unknown value; announcements "Recording in 3", "2", "1", "Recording started" through the router (S5); a setting change during a countdown does not change its length (spec Edge Cases)

## Phase 4: User Story 2 - Cancel a countdown (P1)

**Goal**: cancelling leaves nothing behind.
**Independent test**: manual-clock unit tests and the UI test.

- [ ] REC-007-T09 [US2] Implement `cancelCountdown(_:)` (generation forward, timer cancelled, state idle, `lastCountdownCancel`) and the automatic cancellations in `checkContext()` and `appEnteredBackground()` (REC-007-R5, R6; research D6) in Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator+Countdown.swift
- [ ] REC-007-T10 [US2] Acceptance tests in Apps/projectM-iOS/Tests/RecordingCountdownAppTests.swift: 3 s countdown cancelled at 1.5 s → 0 writer creations, no file in the recordings folder, state idle, nothing starts after advancing past 3 s (REC-007-S1); backgrounding cancels with 0 writers (S4); leaving the visualizer and a lost source cancel; a refusal at the tap starts no countdown
- [ ] REC-007-T11 [US2] UI test in Apps/projectM-iOS/UITests/RecordingCountdownUITests.swift: Settings → Recording countdown 3 s, Record, `recordingCountdown` visible, `recordingCountdownCancel`, no `recordingIndicator`, probe still `none` (REC-007-S6, under 30 s)

## Phase 5: Polish

- [ ] REC-007-T12 Audit that only the Record control calls `toggle()` and no OSC/MIDI action starts or cancels a countdown (`grep` over Apps/projectM-iOS; REC-007-R10, research D10); repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), the type-check budget flags on the touched files, StatusEventsTests completeness (X9d, X9e), existing recording app tests unchanged, privacy manifest and network symbols on the built app
- [ ] REC-007-T13 {device} On D1: 3 s countdown with VoiceOver on, let it complete and cancel once; the recording starts after "1" and a cancel leaves no file

## Dependencies

T01 → T02 → T03 → (T04, T05, T06, T07 in any order) → T08; T03 → T09 → T10, T11; T12 last. US2 builds on US1's state machine.

## Parallel examples

- T05 and T06 touch different new view files and can be written together.
- T08 and T10 share one test file: one writer.

## Implementation strategy

MVP: T01-T03 and T08 (the coordinator proven by the manual clock), then UI and announcements, then cancellation tests and the UI test.
