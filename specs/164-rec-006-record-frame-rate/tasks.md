# Tasks: REC-006 Record frame rate

**Input**: `specs/164-rec-006-record-frame-rate/` (spec, plan, research, data-model, contracts/frame-rate.md, quickstart)
**Tests**: requested by the roadmap acceptance (fixture: nominal rate and bounded drops) and the brief (decimation, unsupported rates disabled, picker UI test).

## Phase 1: Setup

- [ ] REC-006-T01 Write the ADR amending ADR-0027 decision 2 (exact frame grid, nearest-frame pacing, empty slots counted not repeated; research REC-006-D1 to D3) in docs/adr/00NN-recording-frame-grid.md (next free number at commit time)

## Phase 2: Foundational

- [ ] REC-006-T02 Rewrite `RecordingTimeline` to the slot grid (contract C1: slot m = (t × fps + 500_000_000) / 1_000_000_000, ticks m × 600/fps, nearest-frame deferral with d ≤ one slot and the 1.5 d margin, `droppedNotIncreasing` for t ≤ last written time or before the origin, `durationReached` on the slot time; same public API; constant integer work per frame, no wait, no GPU copy, REC-006-R2, R3, R11) in Packages/Compositor/Sources/FrameRecording/RecordingTimeline.swift, and update Packages/Compositor/Tests/FrameRecordingTests/RecordingRulesTests.swift to the grid (120 Hz → 30 fps every 20 ticks; slower loops on the grid with gaps)
- [ ] REC-006-T03 Add `droppedSlots` to `RecordingStatistics` (RecordingFrameGate.swift), count `(tick − last) / interval − 1` per append in `MetalFrameRecorder` (contract C2), and add `frameRate` and `droppedFrames` to `RecordedVideo` (RecordingOutcome.swift); update MetalFrameRecorderTests' stalled-writer case to assert the 9 empty slots

## Phase 3: User Story 1 - Record at a chosen export rate (P1) MVP

**Goal**: 24/30/60 fps files on an exact grid with the nearest frames.
**Independent test**: decimation unit test and the GPU fixture.

- [ ] REC-006-T04 [P] [US1] Unit tests in Packages/Compositor/Tests/FrameRecordingTests/RecordingFrameRateTests.swift: 60 Hz → 24 fps picks, for every slot, the frame nearest the slot (brute force, ties to the earlier) (REC-006-S3); 120 Hz → 30 and 60 give 0 drops and ticks m × I; jittery 120 Hz ± 2 ms drops ≤ 1%
- [ ] REC-006-T05 [US1] Add `RecordingFrameRateChoice` (raw values `profile`, `24`, `30`, `60`; unknown → `profileDefault`), `RecordingQualityProfile.settings(frameRate:)` and a frame-rate override in `RecordingQualityCatalog.availability/resolve` (REC-005 unchanged when nil) in Packages/Compositor/Sources/FrameRecording/RecordingFrameRate.swift and RecordingQualityAvailability.swift / RecordingQualityProfile.swift (REC-006-R1, R12)
- [ ] REC-006-T06 [US1] Report `trackNominalFrameRate` and `minFrameDurationTicks` in `RecordedVideoInfo` (RecordedVideoInspector.swift, REC-006-R5) and add the acceptance fixture in Packages/Compositor/Tests/FrameRecordingTests/RecordingFrameRateFixtureTests.swift (research D8: 64×48, offline writer, 1 s per case; steady 60 Hz and 120 Hz at 24/30/60, one 200 ms stall at 24/30/60, jitter at 24 and 60; nominal rate = selection, ticks exactly m × I, drops = the injected stall's empty slots, 0 for steady) (REC-006-S1, S2)
- [ ] REC-006-T07 [US1] App: `frameRate` choice in `RecordingQualitySetting` (key `settings.recording.frameRate`, nothing stored until changed, reset by `-uitestResetNotice`) in Apps/projectM-iOS/Coordinators/RecordingQualitySetting.swift; the key in `ALLOWED_KEYS` (scripts/run_device_tests.py), `excludedKeys` (Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift) and the Settings erase (LibraryErasePolicy.swift) (REC-006-R8)
- [ ] REC-006-T08 [US1] Resolve the rate at Record in `VideoRecordingCoordinator.start` (Context `frameRateChoice`, `RecordingFrameRateCatalog.resolve`, notice, `lastRecording`) in Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift and pass the choice from AppCoordinator.swift (REC-006-R7, R10)
- [ ] REC-006-T09 [US1] Add `RecordingFrameRateSection` (four rows, reasons, checkmark, accessibility, identifiers `recordingFrameRate.<raw>`) in Apps/projectM-iOS/Views/RecordingFrameRateSection.swift and wire it after `RecordingQualitySection` in SettingsView.swift; profile rows describe the effective rate (REC-006-R9)

## Phase 4: User Story 2 - Dropped frames counted and bounded (P1)

**Goal**: the result reports empty slots; steady rendering reports 0.
**Independent test**: the fixture's stall cases and an app test.

- [ ] REC-006-T10 [US2] App test in Apps/projectM-iOS/Tests/RecordingFrameRateAppTests.swift: a 24 fps recording through the coordinator reads back at 24 fps and `lastRecording` reports its rate and dropped count; changing the choice during a recording leaves that recording's rate unchanged (REC-006-R4, R10)

## Phase 5: User Story 3 - Unsupported rates disabled (P2)

**Goal**: disabled rows with reasons; Record falls back with the X9c notice.
**Independent test**: injected capabilities.

- [ ] REC-006-T11 [US3] Add `RecordingRenderLimit`, `RecordingFrameRateUnavailableReason`, the capability protocol's `renderLimit` and `maxEncodedFramesPerSecond` (defaults nil and 60) and `RecordingFrameRateCatalog.availability/resolve` (contracts C3, C4) in RecordingFrameRate.swift / RecordingQualityAvailability.swift; app capabilities read the render cap from `QualityGovernor` rules (Low Power Mode, thermal) in RecordingQualitySetting.swift
- [ ] REC-006-T12 [P] [US3] Tests: 30 fps display, Low Power cap and a 30 fps encoder limit disable 60 only with the matching reason; resolution falls back 60 → 30 with "Recording at 30 fps: …"; Profile default High on a 30 fps display still falls back to Standard (REC-005) and in Low Power records High at 30 (REC-006-S4) in RecordingFrameRateTests.swift; app: an unavailable row cannot be picked, Record with 60 under a Low Power cap records 30 fps with an X9c notice, in RecordingFrameRateAppTests.swift
- [ ] REC-006-T13 [US3] UI test (under 30 s) in Apps/projectM-iOS/UITests/RecordingFrameRateUITests.swift: the section lists four rows, Profile default selected; tapping 24 fps selects it (REC-006-S5)

## Phase 6: Polish

- [ ] REC-006-T14 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), Linux-shape build of FrameRecording, the type-check budget on the changed app files, privacy manifest and network symbols on the Debug app
- [ ] REC-006-T15 {device} On D1: a 24 fps recording of a 60 Hz projectM visual reads back at 24 fps on the grid with its reported dropped count (REC-006-S6)

## Dependencies

T01 any time. T02 → T03 → T04, T06. T05 → T06 (settings), T07 → T08 → T09, T10. T11 → T08 (resolution), T12, T13. T14 last; T15 needs a device.

## Parallel

T04 and T12's package tests are separate files; T01 is independent. App work (T07-T13) follows the package.

## Implementation strategy

MVP = Phase 2 + US1 (grid, choice, fixture). Then US2's report and US3's availability, then polish.
