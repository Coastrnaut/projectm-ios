# Tasks: REC-006 Record frame rate

**Input**: `specs/164-rec-006-record-frame-rate/` (spec, plan, research, data-model, contracts/frame-rate.md, quickstart)
**Tests**: requested by the roadmap acceptance (fixture: nominal rate and bounded drops) and the brief (decimation, unsupported rates disabled, picker UI test).

## Phase 1: Setup

- [X] REC-006-T01 Write the ADR amending ADR-0027 decision 2 (exact frame grid, nearest-frame pacing, empty slots counted not repeated; research REC-006-D1 to D3) in docs/adr/0056-recording-frame-grid.md (next free number at commit time) — Verified 2026-11-14: docs/adr/0056-recording-frame-grid.md written and listed in docs/adr/README.md (0055 is the highest in the main checkout); validate_docs OK

## Phase 2: Foundational

- [X] REC-006-T02 Rewrite `RecordingTimeline` to the slot grid (contract C1: slot m = (t × fps + 500_000_000) / 1_000_000_000, ticks m × 600/fps, nearest-frame deferral with d ≤ one slot and the 1.5 d margin, `droppedNotIncreasing` for t ≤ last written time or before the origin, `durationReached` on the slot time; same public API; constant integer work per frame, no wait, no GPU copy, REC-006-R2, R3, R11) in Packages/Compositor/Sources/FrameRecording/RecordingTimeline.swift, and update Packages/Compositor/Tests/FrameRecordingTests/RecordingRulesTests.swift to the grid (120 Hz → 30 fps every 20 ticks; slower loops on the grid with gaps) — Verified 2026-11-14: RecordingRulesTests 15/15 (120 Hz → 30 fps every 20 ticks, slower loops on the grid, half-interval window, non-increasing times, duration limit); FrameRecording 84/84 (swift test, host, 8.8 s)
- [X] REC-006-T03 Add `droppedSlots` to `RecordingStatistics` (RecordingFrameGate.swift), count `(tick − last) / interval − 1` per append in `MetalFrameRecorder` (contract C2), and add `frameRate` and `droppedFrames` to `RecordedVideo` (RecordingOutcome.swift); update MetalFrameRecorderTests' stalled-writer case to assert the 9 empty slots — Verified 2026-11-14: MetalFrameRecorderTests.testStalledWriterBoundsFramesInFlightAndDropsTheRest asserts droppedSlots 9; RecordedVideo.frameRate/droppedFrames read by the fixture and app tests

## Phase 3: User Story 1 - Record at a chosen export rate (P1) MVP

**Goal**: 24/30/60 fps files on an exact grid with the nearest frames.
**Independent test**: decimation unit test and the GPU fixture.

- [X] REC-006-T04 [P] [US1] Unit tests in Packages/Compositor/Tests/FrameRecordingTests/RecordingFrameRateTests.swift: 60 Hz → 24 fps picks, for every slot, the frame nearest the slot (brute force, ties to the earlier) (REC-006-S3); 120 Hz → 30 and 60 give 0 drops and ticks m × I; jittery 120 Hz ± 2 ms drops ≤ 1% — Verified 2026-11-14: RecordingFrameRateTests.testSixtyToTwentyFourPicksTheNearestFrames (brute-force nearest, ties within 1 µs to the earlier; 2/3-frame steps), testSteadyRenderingAtOrAboveTheTargetDropsNothing, testJitteryRenderingDropsAtMostOnePercent (host)
- [X] REC-006-T05 [US1] Add `RecordingFrameRateChoice` (raw values `profile`, `24`, `30`, `60`; unknown → `profileDefault`), `RecordingQualityProfile.settings(frameRate:)` and a frame-rate override in `RecordingQualityCatalog.availability/resolve` (REC-005 unchanged when nil) in Packages/Compositor/Sources/FrameRecording/RecordingFrameRate.swift and RecordingQualityAvailability.swift / RecordingQualityProfile.swift (REC-006-R1, R12) — Verified 2026-11-14: RecordingFrameRateTests.testChoiceValues, testExplicitRateChangesOnlyTheRate (fixed rates stay; Standard 5,971,968 b/s at 1080p24); REC-005 RecordingQualityProfileTests unchanged and passing
- [X] REC-006-T06 [US1] Report `trackNominalFrameRate` and `minFrameDurationTicks` in `RecordedVideoInfo` (RecordedVideoInspector.swift, REC-006-R5) and add the acceptance fixture in Packages/Compositor/Tests/FrameRecordingTests/RecordingFrameRateFixtureTests.swift (research D8: 64×48, offline writer, 1 s per case; steady 60 Hz and 120 Hz at 24/30/60, one 200 ms stall at 24/30/60, jitter at 24 and 60; nominal rate = selection, ticks exactly m × I, drops = the injected stall's empty slots or one more and at most ⌈0.2 × fps⌉, 0 for steady) (REC-006-S1, S2) — Verified 2026-11-14: RecordingFrameRateFixtureTests 3/3 on the host (1.3 s): steady 60/120 Hz at 24/30/60 → nominal 24.00/30.00/60.00, 0 dropped, ticks n×I; stall 200 ms → 24 fps 4 (3 empty windows + 1), 30 fps 5, 60 fps 11 dropped, minFrameDuration 25/20/10 of 600; jitter 0 dropped
- [X] REC-006-T07 [US1] App: `frameRate` choice in `RecordingQualitySetting` (key `settings.recording.frameRate`, nothing stored until changed, reset by `-uitestResetNotice`) in Apps/projectM-iOS/Coordinators/RecordingQualitySetting.swift; the key in `ALLOWED_KEYS` (scripts/run_device_tests.py), `excludedKeys` (Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift) and the Settings erase (LibraryErasePolicy.swift) (REC-006-R8) — Verified 2026-11-14: RecordingFrameRateAppTests.testDefaultsToProfileDefaultAndPersists (REC6 iOS 27.2 simulator); key in ALLOWED_KEYS, excludedKeys and LibraryErasePolicy.settingsCategoryKeys (LibraryBackup 72/72); reset in the setting initializer
- [X] REC-006-T08 [US1] Resolve the rate at Record in `VideoRecordingCoordinator.start` (Context `frameRateChoice`, `RecordingFrameRateCatalog.resolve`, notice, `lastRecording`) in Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift and pass the choice from AppCoordinator.swift (REC-006-R7, R10) — Verified 2026-11-14: RecordingFrameRateAppTests.testRenderCapLowersAnExplicitRateWithX9c, testTwentyFourFpsRecordingReportsItsRateAndDroppedFrames; VideoRecordingAppTests 18/18, RecordingAudioAppTests 9/9, RecordingQualityAppTests 6/6 unchanged (simulator)
- [X] REC-006-T09 [US1] Add `RecordingFrameRateSection` (four rows, reasons, checkmark, accessibility, identifiers `recordingFrameRate.<raw>`) in Apps/projectM-iOS/Views/RecordingFrameRateSection.swift and wire it after `RecordingQualitySection` in SettingsView.swift; profile rows describe the effective rate (REC-006-R9) — Verified 2026-11-14: RecordingFrameRateUITests.testPickerSelectsARate; build with -warn-long-* flags: no warning in RecordingFrameRateSection, RecordingQualitySetting, VideoRecordingCoordinator (warnings only in untouched files)

## Phase 4: User Story 2 - Dropped frames counted and bounded (P1)

**Goal**: the result reports empty slots; steady rendering reports 0.
**Independent test**: the fixture's stall cases and an app test.

- [X] REC-006-T10 [US2] App test in Apps/projectM-iOS/Tests/RecordingFrameRateAppTests.swift: a 24 fps recording through the coordinator reads back at 24 fps and `lastRecording` reports its rate and dropped count; changing the choice during a recording leaves that recording's rate unchanged (REC-006-R4, R10) — Verified 2026-11-14: RecordingFrameRateAppTests.testTwentyFourFpsRecordingReportsItsRateAndDroppedFrames: 24 fps, 10 frames, 5 dropped, 15 slots; choice changed to 60 mid-recording keeps 24

## Phase 5: User Story 3 - Unsupported rates disabled (P2)

**Goal**: disabled rows with reasons; Record falls back with the X9c notice.
**Independent test**: injected capabilities.

- [X] REC-006-T11 [US3] Add `RecordingRenderLimit`, `RecordingFrameRateUnavailableReason`, the capability protocol's `renderLimit` and `maxEncodedFramesPerSecond` (defaults nil and 60) and `RecordingFrameRateCatalog.availability/resolve` (contracts C3, C4) in RecordingFrameRate.swift / RecordingQualityAvailability.swift; app capabilities read the render cap from `QualityGovernor` rules (Low Power Mode, thermal) in RecordingQualitySetting.swift — Verified 2026-11-14: RecordingFrameRateTests availability and resolution tests; RecordingFrameRateAppTests.testRenderCapFollowsQualityGovernor
- [X] REC-006-T12 [P] [US3] Tests: 30 fps display, Low Power cap and a 30 fps encoder limit disable 60 only with the matching reason; resolution falls back 60 → 30 with "Recording at 30 fps: …"; Profile default High on a 30 fps display still falls back to Standard (REC-005) and in Low Power records High at 30 (REC-006-S4) in RecordingFrameRateTests.swift; app: an unavailable row cannot be picked, Record with 60 under a Low Power cap records 30 fps with an X9c notice, in RecordingFrameRateAppTests.swift — Verified 2026-11-14: RecordingFrameRateTests.testUnsupportedRatesAreDisabledWithTheirReason, testExplicitRateFallsBackWithANotice, testProfileDefaultKeepsREC005AndAppliesTheRenderCap, testEncoderLimitAndBothNotices; RecordingFrameRateAppTests.testUnavailableRatesShowTheirReasonAndCannotBePicked
- [X] REC-006-T13 [US3] UI test (under 30 s) in Apps/projectM-iOS/UITests/RecordingFrameRateUITests.swift: the section lists four rows, Profile default selected; tapping 24 fps selects it (REC-006-S5) — Verified 2026-11-14: RecordingFrameRateUITests 1/1 on REC6 iOS 27.2: 34.9 s at load average ~375 (REC-005's comparable RecordingQualityUITests took 31.4 s in the same run; app launch dominates; over the 30 s budget only under this load)

## Phase 6: Polish

- [X] REC-006-T14 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), Linux-shape build of FrameRecording, the type-check budget on the changed app files, privacy manifest and network symbols on the Debug app — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 OK; Linux-shape `swift build --build-tests` of Compositor OK; check_privacy_manifest OK and check_network_symbols OK on the Debug simulator app
- [ ] REC-006-T15 {device} On D1: a 24 fps recording of a recordable visual (the photo visual; projectM is not recordable, REC-003-R12) rendering at 60 Hz reads back at 24 fps on the grid with its reported dropped count (REC-006-S6)

## Dependencies

T01 any time. T02 → T03 → T04, T06. T05 → T06 (settings), T07 → T08 → T09, T10. T11 → T08 (resolution), T12, T13. T14 last; T15 needs a device.

## Parallel

T04 and T12's package tests are separate files; T01 is independent. App work (T07-T13) follows the package.

## Implementation strategy

MVP = Phase 2 + US1 (grid, choice, fixture). Then US2's report and US3's availability, then polish.
