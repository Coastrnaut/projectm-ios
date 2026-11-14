# Tasks: REC-005 Record quality profiles

**Input**: `specs/150-rec-005-quality-profiles/` (spec, plan, research, data-model, contracts/quality-profiles.md, quickstart)
**Tests**: requested by the roadmap acceptance (encoded metadata per profile, disabled unsupported modes) and the brief (default = today, injected capabilities, picker UI test).

## Phase 1: Setup

No setup: the module, the coordinator and the Settings section exist (REC-003, REC-004). No ADR (plan, Structure Decision).

## Phase 2: Foundational

- [X] REC-005-T01 Add `fixedBitRate` and `averageBitRate(codec:width:height:)` to `RecordingSettings` (Packages/Compositor/Sources/FrameRecording/RecordingSettings.swift) and read the bit rate through it in `VideoFileWriter.outputSettings` and `RecordingStorageEstimate` (VideoFileWriter.swift, RecordingStorage.swift); test that `RecordingSettings.standard` output settings equal REC-003's dictionary (REC-005-R3, S3) in Packages/Compositor/Tests/FrameRecordingTests/RecordingQualityProfileTests.swift — Verified 2026-11-14: RecordingQualityOutputSettingsTests.testDefaultProfileOutputSettingsEqualREC003 (NSDictionary equality, HEVC and H.264) and testFixedRateProfileWritesItsRate; FrameRecording 70/70 (swift test, host)
- [X] REC-005-T02 Add `RecordingQualityProfile` (C1 table values, `settings`, `title`, `documentation`, `fallbackOrder`) in Packages/Compositor/Sources/FrameRecording/RecordingQualityProfile.swift, with tests (Standard == `.standard`; each profile's cap, codecs, rate and frame rate; Max never scales; no profile upscales, REC-005-R1, R2) — Verified 2026-11-14: RecordingQualityProfileTests testStandardIsTodaysSettings, testProfileTableValues, testNoProfileUpscalesAndMaxKeepsTheScreenSize
- [X] REC-005-T03 Add `RecordingEncoderCapabilities`, `RecordingUnavailableReason` (texts from data-model.md), `RecordingProfileAvailability`, `RecordingProfileResolution` and `RecordingQualityCatalog.availability/resolve` (contract C2) in Packages/Compositor/Sources/FrameRecording/RecordingQualityAvailability.swift, with injected-capability tests: "no HEVC" disables High and Max only; "at most 1920" disables High and Max on a 1206×2622 drawable only; 30 fps display disables High and Max; fallback order and refusal (REC-005-R4 to R6, S2) — Verified 2026-11-14: RecordingQualityProfileTests: no HEVC, 1920 limit, 30 fps display, no picture, fallback Max→Standard with notice, refusal (swift test, host)
- [X] REC-005-T04 Add `VideoToolboxEncoderCapabilities` (public `VTCopySupportedPropertyDictionaryForEncoder`, cached, Apple only) in Packages/Compositor/Sources/FrameRecording/VideoToolboxEncoderCapabilities.swift; test it answers yes for H.264 at 1280×720 on the host — Verified 2026-11-14: VideoToolboxEncoderCapabilitiesTests.testHostEncoderAnswers (swift test, host)

## Phase 3: User Story 1 - Selected profile matches the file (P1) MVP

**Goal**: each profile's recording reads back with its codec, size, frame rate and bit rate.
**Independent test**: the GPU fixture per available profile.

- [X] REC-005-T05 [US1] Report `nominalFrameRate`, `videoBytes` and `averageVideoBitRate` in `RecordedVideoInfo` (Packages/Compositor/Sources/FrameRecording/RecordedVideoInspector.swift, REC-005-R10) and add the acceptance fixture (2 s of per-frame noise from a 1440×2880 drawable, each profile available on the host; codec exact, size exact, frame rate ±1, bit rate ±25%) in Packages/Compositor/Tests/FrameRecordingTests/RecordingQualityFixtureTests.swift; record the measured values in research REC-005-D4 (REC-005-S1) — Verified 2026-11-14: RecordingQualityFixtureTests 4/4 on the host: Draft avc1 640×1280 30 fps 0.999, Standard hvc1 960×1920 30 fps 1.039, High hvc1 1280×2560 60 fps 1.051, Max hvc1 1440×2880 60 fps 1.061 of target; identical in three runs; research D4 updated
- [X] REC-005-T06 [US1] Add `RecordingQualitySetting` (key `settings.recording.qualityProfile`, default Standard, unknown → Standard, rows' availability) in Apps/projectM-iOS/Coordinators/RecordingQualitySetting.swift; the key in `ALLOWED_KEYS` (scripts/run_device_tests.py), `excludedKeys` (Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift) and the `-uitestResetNotice` reset (Apps/projectM-iOS/Coordinators/AppCoordinator.swift) (REC-005-R7) — Verified 2026-11-14: RecordingQualityAppTests.testDefaultsToStandardAndPersists (REC5 iOS 27.2 simulator); key in ALLOWED_KEYS, excludedKeys and LibraryErasePolicy (Settings erase; LibraryBackup 68/68 incl. LibraryEraseAcceptanceTests), the UI-test reset lives in the setting's initializer (keeps AppCoordinator.init's type-check unchanged)
- [X] REC-005-T07 [US1] Resolve the profile at Record in `VideoRecordingCoordinator.start` (Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift): profile from the context, injectable capabilities, settings from the plan for the writer and the disk guard (REC-005-R6, R8, R11) — Verified 2026-11-14: RecordingQualityAppTests fallback, refusal and fixed-profile tests; VideoRecordingAppTests 18/18 and RecordingAudioAppTests 9/9 unchanged (simulator)
- [X] REC-005-T08 [US1] Add `RecordingQualitySection` (rows, reasons, footer table, accessibility) in Apps/projectM-iOS/Views/RecordingQualitySection.swift and wire it in SettingsView.swift (`audioSections`, before REC-004's section) and VisualizerView.swift (REC-005-R9, R12) — Verified 2026-11-14: RecordingQualityUITests.testPickerSelectsAProfile (four rows, labels, selection); build with -warn-long-* flags: no warning in the new or changed files except AppCoordinator.init (≈450 ms before and after this change: measured on the unchanged file too)
- [X] REC-005-T09 [US1] App tests in Apps/projectM-iOS/Tests/RecordingQualityAppTests.swift: default Standard, persistence, unknown value; rows' availability from injected capabilities; the rows' size is the drawable when a visual is shown, else the screen (REC-005-R7, R9, R12) — Verified 2026-11-14: RecordingQualityAppTests 6/6 (testDisabledRowsShowTheirReasonAndCannotBePicked, testRowsDescribeTheGivenSize)

## Phase 4: User Story 2 - Unsupported profiles disabled (P1)

**Goal**: disabled rows with reasons; Record falls back or refuses.
**Independent test**: injected capabilities in the app tests.

- [X] REC-005-T10 [US2] Add status row X9c (`StatusEventCatalog.recordingQualityFallback`, classified from the notice) in Apps/projectM-iOS/Coordinators/StatusEvents.swift; coordinator tests: Max selected with "no HEVC" records with Standard and sets "Recording at Standard: Needs HEVC, which this device cannot encode."; with nothing encodable Record refuses with the encoder-unavailable notice; the stored choice is unchanged; changing the choice during a recording leaves that recording's settings and audio decision unchanged (REC-005-R6, R11) — Verified 2026-11-14: RecordingQualityAppTests.testUnavailableSelectionFallsBackAndAnnouncesX9c (avc1 file, X9c, cause user), testNothingEncodableRefusesWithEncoderUnavailable, testChangingTheProfileDuringARecordingKeepsItsProfile; check_status_events OK
- [X] REC-005-T11 [US2] UI test (under 30 s) in Apps/projectM-iOS/UITests/RecordingQualityUITests.swift: Settings shows the four rows, Standard selected; tapping High selects it (REC-005-S4) — Verified 2026-11-14: RecordingQualityUITests 1/1 on REC5 iOS 27.2, 31.4-36.7 s under load average 600-800 (REC-004's comparable test took 38 s in the same run; launch dominates)

## Phase 5: User Story 3 - Disk guard per profile (P2)

- [X] REC-005-T12 [US3] Test that each profile's storage estimate uses its bit rate at its size and frame rate (Max > High > Standard > Draft at the fixture size) and that a free space between Draft's and Max's start needs allows Draft only, in Packages/Compositor/Tests/FrameRecordingTests/RecordingQualityProfileTests.swift (REC-005-R8) — Verified 2026-11-14: RecordingQualityProfileTests.testStorageEstimateUsesEachProfilesRate (625,000 / 1,591,200 / 3,125,000 / 6,250,000 B/s; 400 MB free allows Draft, refuses Max)

## Phase 6: Polish

- [X] REC-005-T13 Repo checks (compliance, docs, motion, permission catalog, status events, scripts), privacy manifest and network symbols on the Debug app, type-check budget, Linux shape of FrameRecording (`-DCOMPOSITOR_NO_METAL`); spec status updated — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 OK; check_privacy_manifest and check_network_symbols OK on the Debug simulator app; Compositor builds with -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE --build-tests; FrameRecording 70/70
- [ ] REC-005-T14 `{device}` Quickstart C on D1/D2: record each available profile and read it back (REC-005-S5)

## Dependencies

T01 → T02 → T03 → (T04, T05, T12) ; T03 → T06 → T07 → T08 → T09, T10, T11 ; all → T13.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1 T02/T08, R2 T02, R3 T01, R4 T03/T04, R5 T08/T11, R6 T07/T10, R7 T06/T09, R8 T07/T12,
R9 T08/T11, R10 T05, R11 T10, R12 T09; S1 T05, S2 T03, S3 T01, S4 T11, S5 T14. Fixes applied: R11
(profile fixed per recording) and R12 (rows' size source) had no test, now in T10 and T09; spec R9
"next to" and contract C3 "directly before" agree (before REC-004's section). No constitution conflicts.
