# Tasks: REC-007 Recording countdown

**Input**: `specs/175-rec-007-countdown/` (spec, plan, research, data-model, contracts/countdown.md, quickstart)
**Tests**: requested by the roadmap acceptance (cancel prevents file creation; completed countdown starts once) and the brief (Off, background, announcements, UI test).

## Phase 1: Setup

- [X] REC-007-T01 Add `RecordingCountdownLength` (raw values `off`, `3`, `5`, `10`; absent or unknown → `off`), `RecordingCountdownCancel` (user, background, leftVisualizer, visualLost, presentationLost, blackedOut, paused, each with its caption text), the `RecordingCountdownClock`/`RecordingCountdownTimer` protocols and the system clock (`ProcessInfo.systemUptime`, main-actor `Task.sleep`) in Apps/projectM-iOS/Coordinators/RecordingCountdown.swift (research REC-007-D2) — Verified 2026-11-14: RecordingCountdownAppTests (all 10 use these types; testSettingDefaultsToOffAndPersists checks the raw values and seconds 0/3/5/10); build on the REC7 iOS 27.2 simulator

## Phase 2: Foundational

- [X] REC-007-T02 Add `case countingDown(Int)` to `VideoRecordingCoordinator.State` (explicit `allCases` with `countingDown(1)`), route `toggle()`, split `start()` into `start(afterCountdown:)`, count `writerCreations`, run the context check and background observer for countdowns, `filesInUse` only while recording or finishing, inject the clock (`countdownClock` init parameter, default system) and add Context `countdown` in Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift; update every exhaustive switch on the state (StatusEvents.swift X9d row, ControlsOverlay, VisualizerView indicator condition, ExternalDisplay hold unchanged) — Verified 2026-11-14: build-for-testing on REC7 (Debug, -warn-long-* flags: no warning in the touched coordinator files); StatusEventsTests 8/8 (allCases with countingDown(1) has a row), VideoRecordingAppTests 18/18, RecordingAudioAppTests 9/9, RecordingQualityAppTests 6/6, RecordingFrameRateAppTests 5/5, HotPlugAcceptanceTests 7/7 unchanged

## Phase 3: User Story 1 - Start after a countdown (P1) MVP

**Goal**: Record with 3/5/10 s counts down and starts exactly once.
**Independent test**: manual-clock unit tests.

- [X] REC-007-T03 [US1] Implement begin, tick (deadlines start + k), completion (generation token, refusal at completion → idle) and the late-tap guards (0.25 s before completion, 0.5 s after the start) in Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift (MARK Countdown; same file because `state` has a private setter) (REC-007-R2, R3, R4; research D3, D4, D5) — Verified 2026-11-14: RecordingCountdownAppTests.testCompletedCountdownStartsOnceDespiteLateTaps, testSettingChangeDuringACountdownKeepsItsLength, testOffStartsImmediately (manual clock, REC7 simulator)
- [X] REC-007-T04 [US1] Add `RecordingCountdownSetting` (key `settings.recording.countdown`, removed by `-uitestResetNotice`) in Apps/projectM-iOS/Coordinators/RecordingCountdownSetting.swift, own it in AppCoordinator.swift and pass `countdown` in `videoRecordingContext`; add the key to `ALLOWED_KEYS` (scripts/run_device_tests.py) and `includedKeys` (Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift) (REC-007-R1, R8) — Verified 2026-11-14: testSettingDefaultsToOffAndPersists; RecordingCountdownUITests reads the key from the launch arguments; key in ALLOWED_KEYS (test_scripts 159 OK) and includedKeys (LibraryBackup swift test 74/74)
- [X] REC-007-T05 [US1] Add `RecordingCountdownSection` (rows `recordingCountdown.off|3|5|10`, checkmark, selected trait) in Apps/projectM-iOS/Views/RecordingCountdownSection.swift and wire it under the frame-rate section in SettingsView.swift (`audioSections`) and VisualizerView.swift (REC-007-R9) — Verified 2026-11-14: builds; the rows assign `length` (round trip proven by testSettingDefaultsToOffAndPersists). The Settings rows are not driven by a UI test: scrolling to the section took 25 s of the 30 s UI budget (owner rule 7)
- [X] REC-007-T06 [US1] Add the countdown overlay (number, label "Recording in N", Cancel with `.keyboardShortcut(.cancelAction)`, no animation) in Apps/projectM-iOS/Views/RecordingCountdownView.swift, show it in VisualizerView's status area, and make the Record item read "Cancel countdown" in ControlsOverlay.swift (REC-007-R7) — Verified 2026-11-14: RecordingCountdownUITests.testCountdownShowsAndCancelRecordsNothing (`recordingCountdown` label "Recording in …", `recordingCountdownCancel` tapped); check_motion_policy OK; Escape via .cancelAction not driven by a test (no hardware keyboard in XCUITest here)
- [X] REC-007-T07 [US1] Status rows X9d (first "Recording in N", then "N") and X9e (caption; user or system) in Apps/projectM-iOS/Coordinators/StatusEvents.swift, posted from StatusCaptionView.swift's `recordingStateChanged` (REC-007-R6, R7; contract C2) — Verified 2026-11-14: testAnnouncementsCountDownThenSayRecordingStarted ("Recording in 3", "2", "1", "Recording started"; then "Recording in 3", "2", "Countdown cancelled", all on the recording lane), testCountdownRows; check_status_events OK
- [X] REC-007-T08 [US1] Acceptance and unit tests in Apps/projectM-iOS/Tests/RecordingCountdownAppTests.swift: completed 3 s countdown → exactly 1 writer creation, a second toggle at 2.99 s and at 3.0 s (before and after the tick) adds no recording and no stop (REC-007-S2); Off starts in the same call (S3); setting persistence and unknown value; announcements "Recording in 3", "2", "1", "Recording started" through the router (S5); a setting change during a countdown does not change its length (spec Edge Cases) — Verified 2026-11-14: RecordingCountdownAppTests 10/10 on REC7 (1.2 s for the class)

## Phase 4: User Story 2 - Cancel a countdown (P1)

**Goal**: cancelling leaves nothing behind.
**Independent test**: manual-clock unit tests and the UI test.

- [X] REC-007-T09 [US2] Implement `cancelCountdown(_:)` (generation forward, timer cancelled, state idle, `lastCountdownCancel`) and the automatic cancellations in `checkContext()` and `appEnteredBackground()` (REC-007-R5, R6; research D6) in Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift (MARK Countdown; same file because `state` has a private setter) — Verified 2026-11-14: testBackgroundingCancels, testLeavingTheVisualizerAndALostSourceCancel, testRefusalStartsNoCountdownAndCancelIsAlwaysHonored
- [X] REC-007-T10 [US2] Acceptance tests in Apps/projectM-iOS/Tests/RecordingCountdownAppTests.swift: 3 s countdown cancelled at 1.5 s → 0 writer creations, no file in the recordings folder, state idle, nothing starts after advancing past 3 s (REC-007-S1); backgrounding cancels with 0 writers (S4); leaving the visualizer and a lost source cancel; a refusal at the tap starts no countdown — Verified 2026-11-14: testCancelAtOneAndAHalfSecondsCreatesNoFile (writerCreations 0, recordings folder empty, state idle, no tap, nothing scheduled, probe none) and the three cancellation tests
- [X] REC-007-T11 [US2] UI test in Apps/projectM-iOS/UITests/RecordingCountdownUITests.swift: Settings → Recording countdown 3 s, Record, `recordingCountdown` visible, `recordingCountdownCancel`, no `recordingIndicator`, probe still `none` (REC-007-S6, under 30 s) — Verified 2026-11-14: RecordingCountdownUITests 1/1, 15.7 s on REC7 (Record → Cancel 0.8 s apart)

## Phase 5: Polish

- [X] REC-007-T12 Audit that only the Record control calls `toggle()` and no OSC/MIDI action starts or cancels a countdown (`grep` over Apps/projectM-iOS; REC-007-R10, research D10); repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), the type-check budget flags on the touched files, StatusEventsTests completeness (X9d, X9e), existing recording app tests unchanged, privacy manifest and network symbols on the built app — Verified 2026-11-14: grep: only ControlsOverlay.swift calls recording.toggle() (lines 340, 349); check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 OK; check_privacy_manifest OK and check_network_symbols OK on the Debug simulator .app; ControlsOverlay/SettingsView/VisualizerView have one expression each at 185-195 ms (under the 200 ms limit, at lines this feature did not change)
- [ ] REC-007-T13 {device} On D1: 3 s countdown with VoiceOver on, let it complete and cancel once; the recording starts after "1" and a cancel leaves no file

## Dependencies

T01 → T02 → T03 → (T04, T05, T06, T07 in any order) → T08; T03 → T09 → T10, T11; T12 last. US2 builds on US1's state machine.

## Parallel examples

- T05 and T06 touch different new view files and can be written together.
- T08 and T10 share one test file: one writer.

## Implementation strategy

MVP: T01-T03 and T08 (the coordinator proven by the manual clock), then UI and announcements, then cancellation tests and the UI test.
