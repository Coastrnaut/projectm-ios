# Tasks: REC-009 Recording status overlay

**Input**: `specs/190-rec-009-status-overlay/` (spec, plan, research, data-model, contracts/status-overlay.md, quickstart)
**Tests**: requested by the roadmap acceptance (the export never includes the control overlay) and the brief (exclusion read-back, dropped count from the recorder statistics, storage thresholds, throttled announcements, a UI test under 30 s).

## Phase 1: Setup

No setup: no new package, setting, key or dependency.

## Phase 2: Foundational (FrameRecording)

- [ ] REC-009-T01 [P] Add `RecordingStatusSummary` (fields `droppedSlots`, `writtenFrames`, `availableBytes: Int64?`, `secondsLeft: Int64?`; `droppedWarning` = "`dropped ≥ 10 && dropped × 50 ≥ written + dropped`"; `storageLevel` `.ok`/`.low` (< 300 s)/`.critical` (< 60 s), nil when unknown; texts "Dropped frames: 3", "Dropping frames: 12 (3%)", "2.1 GB free, about 14 min left", "850 MB free, under 1 min left", "Free storage unknown"; seconds left from `RecordingStoragePolicy.stopThreshold` and the larger of the estimated and measured rates), `RecordingWarningKind`, `RecordingWarningThrottle` (rising levels only, ≥ 30 s of recorded time between two announcements of one kind) in Packages/Compositor/Sources/FrameRecording/RecordingStatusSummary.swift (data model; research REC-009-D2 to D4)
- [ ] REC-009-T02 [P] Package tests in Packages/Compositor/Tests/FrameRecordingTests/RecordingStatusSummaryTests.swift: dropped threshold edges (9/10 drops, 2% boundary), byte formatting (GB/MB), minutes left with estimate vs measured rate, level edges (300 s, 60 s, below the threshold), unknown storage, throttle (first rise, no repeat at the same level, 30 s gap, critical after low, fall to none then rise) (REC-009-R2, R3, R4, R8; S2-S4)

## Phase 3: User Story 1 - See how the recording is going (P1) MVP

**Goal**: the dropped and storage lines under the indicator while recording, warnings announced once.
**Independent test**: coordinator wiring tests with the fake source and a settable storage probe; the UI test.

- [ ] REC-009-T03 [US1] Coordinator in Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift: keep the Record-time and 5 s storage readings (available bytes, file bytes), `statusSummary` refreshed in `checkContext` and after `checkStorage`, nil outside `.recording`; `RecordingWarningThrottle` reset at start; `statusWarning` (with a sequence number) set when the throttle allows (REC-009-R1 to R4, R7, R8)
- [ ] REC-009-T04 [US1] Status rows X9f ("Recording is dropping frames") and X9g ("Storage low: about N min of recording left" / "Storage almost full: under 1 min of recording left"), recording lane, system cause, in Apps/projectM-iOS/Coordinators/StatusEvents.swift (contract C2)
- [ ] REC-009-T05 [US1] View `RecordingStatusLines` (identifiers `recordingDroppedFrames`, `recordingStorageStatus`; `exclamationmark.triangle` and "Warning: " label prefix when warned; no animation) and the `RecordingStatusEventChanges` modifier posting `statusWarning` through the router, in Apps/projectM-iOS/Views/RecordingStatusLines.swift; one line each in VisualizerView.swift (under `RecordingAudioLine`) and StatusCaptionView.swift; add the file to `CHECKED` in scripts/check_status_events.py (contract C1; REC-009-R1, R5)
- [ ] REC-009-T06 [US1] App tests in Apps/projectM-iOS/Tests/RecordingStatusOverlayAppTests.swift: the summary's dropped count equals `recorder.statistics.droppedSlots` after fed frames with gaps; storage readings at start and from `checkStorage` drive the line and its level; a falling free space raises low then critical, posted once each through a router with a fake announcer; repeated readings post nothing more; summary nil when idle (REC-009-S2 to S4)
- [ ] REC-009-T07 [US1] UI test in Apps/projectM-iOS/UITests/RecordingStatusOverlayUITests.swift: Photo visual, Record, the indicator, "Dropped frames: …" and "… free, about … min left" lines exist, Stop (REC-009-S5, under 30 s)

## Phase 4: User Story 2 - The recording never shows the app's controls (P1)

**Goal**: prove no app UI reaches a recording.
**Independent test**: read every recorded frame back.

- [ ] REC-009-T08 [US2] Acceptance test `testOverlayIsNeverInTheRecording` in Apps/projectM-iOS/Tests/RecordingStatusOverlayAppTests.swift: Photo visual with a solid red PNG in a window, a `UIHostingController` on top with a green `#00FF00` probe with text and the real `RecordingStatusLines`; a window snapshot shows the probe; record ≥ 10 frames through the coordinator, finish, decode every frame with AVAssetReader (BGRA): no green-dominant pixel anywhere, and every pixel outside the central spectrum disc within tolerance of red (REC-009-R6, S1; research D6)
- [ ] REC-009-T09 [US2] Record research REC-009-D1 (encodeOutput, the spectra's drawable blit, the external display path, the flash guard) in the comments of VideoRecordingCoordinator.swift and in the spec's status (REC-009-R6)

## Phase 5: Polish

- [ ] REC-009-T10 Repo checks (check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events, test_scripts), type-check budget build, check_privacy_manifest on the Debug app, check_network_symbols; tick tasks with evidence; spec status
- [ ] REC-009-T11 {device} On D1, record the Photo visual, look at the lines (and a low-storage warning on a nearly full device), save the file and confirm the lines are not in it

## Dependencies

T01 → T02, T03 → T04, T05 → T06, T07; T08 needs T05 (the real view); T09 any time; T10 last.

## Parallel examples

T01 and T02 together; T04 and T05 after T03.

## Implementation strategy

MVP: T01-T06 and T08 (lines plus the exclusion proof); then the UI test and polish.
