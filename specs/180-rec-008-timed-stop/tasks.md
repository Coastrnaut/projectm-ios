# Tasks: REC-008 Timed recording stop

**Input**: `specs/180-rec-008-timed-stop/` (spec, plan, research, data-model, contracts/timed-stop.md, quickstart)
**Tests**: requested by the roadmap acceptance (ten-second target closes the file with a readable index and no extra frames) and the brief (24/30/60 fps, jittery 60 Hz, audio, render-thread spy, manual and disk-guard stops, persistence, UI test).

## Phase 1: Setup

- [ ] REC-008-T01 Add `RecordingTimedStopLength` (raw values `off`, `10`, `30`, `60`, `300`; seconds 0/10/30/60/300; titles "Off", "10 seconds", "30 seconds", "1 minute", "5 minutes"; `stoppedNotice` "Recording stopped after <title>."; absent or unknown → `off`) and `RecordingTimedStopSetting` (key `settings.recording.timedStop`, removed by `-uitestResetNotice`, DEBUG `-uitestTimedStop <raw>`) in Apps/projectM-iOS/Coordinators/RecordingTimedStop.swift (data model; research REC-008-D4)

## Phase 2: Foundational (FrameRecording)

- [ ] REC-008-T02 [P] Add `limitSample: Int64?` to `RecordingAudioTimeline` (nothing placed at or after it; a straddling chunk is cut) with cases in Packages/Compositor/Tests/FrameRecordingTests/RecordingAudioTimelineTests.swift (REC-008-R4; research D3)
- [ ] REC-008-T03 Add `MetalFrameRecorder.beginFinish()` (starts the finish task under the lock, returns at once, idempotent with `finish()`) and set the audio timeline's limit from `settings.maxDurationSeconds` in Packages/Compositor/Sources/FrameRecording/MetalFrameRecorder.swift; add `RecordingStopReason.timedStop` in RecordingOutcome.swift (REC-008-R3; research D2, D5; contract C2)

## Phase 3: User Story 1 - Record exactly a set length (P1) MVP

**Goal**: a 10 s length gives exactly fps × 10 frames, a 10 s duration, a playable file, audio to 10 s.
**Independent test**: package fixtures with injected frame times.

- [ ] REC-008-T04 [US1] Acceptance fixtures in Packages/Compositor/Tests/FrameRecordingTests/RecordingTimedStopTests.swift: 10 s length at 24, 30, 60 fps and a jittery 60 Hz render at 30 fps, frames offered past 10 s until `durationReached`, then `beginFinish()`; read back with `RecordingValidator.validate` (duration 10 s, no issues) and `RecordedVideoInspector` (playable, exactly fps × 10 frames, last tick < 6,000, duration within one frame of 10 s); audio case ends within 20 ms of 10 s (REC-008-S1, S2; contract C1)
- [ ] REC-008-T05 [US1] Render-thread spy in RecordingTimedStopTests.swift: a sink whose `finish` is held by the test; `recordFrame` and `beginFinish` return while the finish is held, no sink `finish` runs on the calling thread, later frames return `.finished` (REC-008-S3; contract C2)
- [ ] REC-008-T06 [US1] Coordinator: Context `timedStop`, the length fixed at start (`recordingLength`), `settings.maxDurationSeconds = min(length, limit)`, `durationReached` with a length → `.timedStop` with the length's notice, the indicator text "0:07 / 0:10" (`elapsedWithLengthText`) in Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift; the tap pumps audio then calls `recorder.beginFinish()` on `durationReached` (REC-008-R2, R3, R6, R7, R8, R10)
- [ ] REC-008-T07 [US1] Status: X13 for `timedStop` and the "Recording stopped after " notices in Apps/projectM-iOS/Coordinators/StatusEvents.swift; the recording indicator (Apps/projectM-iOS/Views/VisualizerView.swift, `recordingIndicator`: cue text `indicatorText` "0:07 / 0:10", label "Recording, 0:07 of 0:10") and the Record item's value in Apps/projectM-iOS/Views/ControlsOverlay.swift (REC-008-R7, R8)
- [ ] REC-008-T08 [US1] Own the setting in Apps/projectM-iOS/Coordinators/AppCoordinator.swift and pass `timedStop` in the recording context; add `RecordingTimedStopSection` (rows `recordingTimedStop.<raw>`) in Apps/projectM-iOS/Views/RecordingTimedStopSection.swift wired in SettingsView.swift and VisualizerView.swift; add the key to `ALLOWED_KEYS` (scripts/run_device_tests.py), `includedKeys` (Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift) and the LibraryBackupAppTests key list (REC-008-R1, R9)
- [ ] REC-008-T09 [US1] App tests in Apps/projectM-iOS/Tests/RecordingTimedStopAppTests.swift: setting default Off, persistence, unknown value; a `durationReached` report with 10 s → `lastStopReason == .timedStop`, notice "Recording stopped after 10 seconds.", X13 classification; Off → `.durationReached` unchanged; the length is fixed at start (a change during the recording is ignored, R10); a 3 s countdown before a 10 s length leaves the length counted from the recording's start (R6); indicator text (REC-008-R8, S5)
- [ ] REC-008-T10 [US1] UI test in Apps/projectM-iOS/UITests/RecordingTimedStopUITests.swift: `-uitestTimedStop 10`, Photo visual, Record, wait for the stop, the probe reads a finished file of 10.0 s (REC-008-S5)

## Phase 4: User Story 2 - Other stops still win (P1)

- [ ] REC-008-T11 [US2] App tests in RecordingTimedStopAppTests.swift: with a 10 s length, a manual stop gives `.user` and no timed notice; a disk-guard stop (scripted storage probe) gives `.lowStorage` and its notice (REC-008-R5, S4)
- [ ] REC-008-T12 [US2] Package test in RecordingTimedStopTests.swift: a recorder with a 10 s length finished at 4 s of frames gives a file of 4 s (no padding) (REC-008-R5)

## Phase 5: Polish

- [ ] REC-008-T13 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), Compositor package tests on the host, the type-check budget flags on touched files, existing recording app tests unchanged, privacy manifest and network symbols on the built app, Linux-safe FrameRecording (pure Swift only in the timeline)
- [ ] REC-008-T14 {device} On D1: 10 s length, record the Photo visual, Save, validate the file (10 s, 300 frames at 30 fps)

## Dependencies

T01 → T06, T08. T02 → T03 → T04, T05, T12. T06 → T07, T09, T10, T11. T13 last.

## Parallel opportunities

T02 and T01 (different files). T04/T05/T12 share one file (sequential). T09/T11 share one file.

## Implementation strategy

MVP = Phase 2 + T04 (the acceptance in the package), then the app wiring and UI test.
