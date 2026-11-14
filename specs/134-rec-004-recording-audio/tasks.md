# Tasks: REC-004 Recording audio mux

**Input**: `specs/134-rec-004-recording-audio/` (spec, plan, research, data-model, contracts/recording-audio.md, quickstart)
**Tests**: requested by the roadmap acceptance (fixture encoding, consent, system capture, switch, UI toggle).

## Phase 1: Setup

- [X] REC-004-T01 Write ADR-0053 "Recording audio policy" (owned and consented audio only, decision at Record, end on switch, no silent track, consent excluded from backup, privacy-rule reconciliation) in docs/adr/0053-recording-audio-policy.md and list it in docs/adr/README.md — Verified 2026-11-14: docs/adr/0053-recording-audio-policy.md and README row; validate_docs OK

## Phase 2: Foundational

- [X] REC-004-T02 [P] Add `RecordingAudioSourceKind`, `RecordingAudioDecision` (reasons and status texts verbatim from data-model.md) and `RecordingAudioPolicy.decide(source:includeMicrophone:microphoneGranted:)` per contract C1 in Packages/Compositor/Sources/FrameRecording/RecordingAudioPolicy.swift, with tests in Packages/Compositor/Tests/FrameRecordingTests/RecordingAudioPolicyTests.swift — Verified 2026-11-14: RecordingAudioPolicyTests 5/5 (swift test, Compositor)
- [X] REC-004-T03 [P] Add `RecordingAudioTimeline` (44,100 Hz, "contiguityWindowSamples 4,410 (100 ms)", origin, trim before origin, overlap trim, gap re-anchor, `end()`) in Packages/Compositor/Sources/FrameRecording/RecordingAudioTimeline.swift, with tests in Packages/Compositor/Tests/FrameRecordingTests/RecordingAudioTimelineTests.swift — Verified 2026-11-14: RecordingAudioTimelineTests 7/7 (swift test, Compositor)
- [X] REC-004-T04 [P] Add the recording tap to `NormalizedPCMRing` (22,050-frame SPSC ring, armed flag, `Atomic<WordPair>` stamp, disarm in `reset()`/`resetForHandoff()`, drain in `discardBuffered()`) and `RecordingTapReading`/`RecordingTapChunk` in Packages/AudioCore/Sources/AudioCore/NormalizedPCMReader.swift and Packages/AudioCore/Sources/AudioCore/RecordingTap.swift; expose `CaptureManager.recordingTap` in Packages/CaptureKit/Sources/CaptureKit/CaptureManager.swift; tests in Packages/AudioCore/Tests/AudioCoreTests/RecordingTapTests.swift (disarmed writes nothing; stamp gives the first sample's time; reset/handoff disarm before new-session audio; overflow drops oldest and counts, REC-004-R8; the tap holds the samples written to the main ring, i.e. before trim and gate, REC-004-R12) — Verified 2026-11-14: RecordingTapTests 7/7, AudioCore 198/198 (swift test); CaptureKit builds

## Phase 3: User Story 1 - Owned audio in sync (P1) MVP

**Goal**: recordings of In-App Playback have an AAC track aligned with the video.
**Independent test**: the owned-audio fixture: click and flash ≤ 20 ms apart.

- [X] REC-004-T05 [US1] Add the optional AAC input (AAC-LC, 44.1 kHz, stereo, 128 kb/s) and LPCM sample-buffer appends to `VideoFileWriter` and `RecordingSampleSink` in Packages/Compositor/Sources/FrameRecording/VideoFileWriter.swift — Verified 2026-11-14: RecordingAudioMuxTests (real AVAssetWriter, AAC track read back)
- [X] REC-004-T06 [US1] (also guarantees contract C3: a recorder made with `audio: true` that never receives audio writes no audio track; tested in T09) Add `audio:` to `MetalFrameRecorder.init`, `appendAudio(_:frames:firstSampleNanoseconds:)`, `endAudio()`, audio statistics and the video origin hand-off in Packages/Compositor/Sources/FrameRecording/MetalFrameRecorder.swift and RecordingFrameGate.swift — Verified 2026-11-14: RecordingAudioMuxTests 7/7 and MetalFrameRecorderTests 8/8; FrameRecording 52/52
- [X] REC-004-T07 [US1] Report audio codec, sample rate and channel count in `RecordedVideoInfo` in Packages/Compositor/Sources/FrameRecording/RecordedVideoInspector.swift — Verified 2026-11-14: testOwnedAudioClickAlignsWithFlash asserts "aac ", 44,100 Hz, 2 channels
- [X] REC-004-T08 [US1] Acceptance fixture `testOwnedAudioClickAlignsWithFlash` (research D7) plus "audio before the first frame is trimmed" in Packages/Compositor/Tests/FrameRecordingTests/RecordingAudioMuxTests.swift — Verified 2026-11-14: testOwnedAudioClickAlignsWithFlash (click within 20 ms of the flash at 1.0 s) and testAudioBeforeTheFirstFrameIsLeftOut; three consecutive runs, 0 frames dropped

## Phase 4: User Story 2 - Microphone consent (P1)

**Goal**: microphone audio only with the permission and the setting.
**Independent test**: consent off or permission denied → no audio track; both on → track with the samples.

- [X] REC-004-T09 [US2] Consent fixture tests (policy decision drives `audio:`; samples offered in every case; `audio: true` with no chunk → no audio track) in Packages/Compositor/Tests/FrameRecordingTests/RecordingAudioMuxTests.swift — Verified 2026-11-14: testMicrophoneWithoutConsentLeavesNoAudio, testMicrophoneWithConsentIsRecorded, testIncludeWithNoAudioOfferedWritesNoAudioTrack
- [X] REC-004-T10 [US2] Add `RecordingAudioSetting` (key `settings.recording.includeMicrophone`, "Bool, default false (absent or not a Bool → false)") in Apps/projectM-iOS/Coordinators/RecordingAudioSetting.swift; add the key to `ALLOWED_KEYS` in scripts/run_device_tests.py, `LibrarySettingsPolicy.excludedKeys` and the erase's device switches in Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift and LibraryErasePolicy.swift, the `-uitestResetNotice` reset in Apps/projectM-iOS/Coordinators/AppCoordinator.swift, and the app key-list tests — Verified 2026-11-14: RecordingAudioAppTests.testSettingDefaultsOffAndPersists; LibraryBackupAppTests, LibraryEraseAppTests; LibraryBackup package 44/44; test_scripts 153 OK
- [X] REC-004-T11 [US2] Update docs/privacy-policy.md and the catalog's microphone `features` in Apps/projectM-iOS/Coordinators/PermissionCatalog.swift (REC-004-R11; the usage description itself stays, FR-019) — Verified 2026-11-14: check_permission_catalog OK; PermissionCatalogTests pass

## Phase 5: User Story 3 - Other apps' audio never recorded (P1)

**Goal**: System/App Capture recordings are video only; a switch ends audio.
**Independent test**: system capture → no audio track; switch mid-recording → audio ends within 20 ms.

- [X] REC-004-T12 [US3] Fixture tests: system capture offered audio → no audio track; `endAudio()` at a switch → last audio sample within 20 ms of the switch, video continues, in Packages/Compositor/Tests/FrameRecordingTests/RecordingAudioMuxTests.swift — Verified 2026-11-14: testSystemCaptureNeverHasAnAudioTrack, testASwitchEndsTheAudioAndTheVideoGoesOn (last audio within 20 ms of the switch, video 2.0 s)
- [X] REC-004-T13 [US3] Wire the decision into `VideoRecordingCoordinator` (context: mode, permission, setting, tap; arm only on include; drain per frame through `VideoRecordingTap`; early end on mode change, disarm or setting off) in Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift and the context in Apps/projectM-iOS/Coordinators/AppCoordinator.swift — Verified 2026-11-14: RecordingAudioAppTests 9/9 on REC4 (iOS 27.2 simulator): app audio, no audio for system capture and missing consent, switch, new session, consent withdrawn; VideoRecordingUITests probe "audio=1"

## Phase 6: User Story 4 - Audio status (P2)

**Goal**: the user knows what audio the recording holds.
**Independent test**: app unit tests of texts and events; UI test of the toggle.

- [X] REC-004-T14 [US4] Status events for "audio at start" and "audio ended" (kind `.recording`) in Apps/projectM-iOS/Coordinators/StatusEvents.swift, posted from Apps/projectM-iOS/Views/StatusCaptionView.swift; update scripts/check_status_events.py lists if required — Verified 2026-11-14: RecordingAudioAppTests.testStatusEventsAreOnTheRecordingLane; StatusEventsTests pass; check_status_events OK
- [X] REC-004-T15 [US4] Settings → Recording section (toggle `recordingMicrophoneToggle`, footer, status `recordingAudioStatus`) in Apps/projectM-iOS/Views/RecordingAudioSection.swift, added to `SettingsView.audioSections`; Record hint in Apps/projectM-iOS/Views/ControlsOverlay.swift; line `recordingAudioLine` under the indicator in Apps/projectM-iOS/Views/VisualizerView.swift — Verified 2026-11-14: RecordingAudioUITests (Settings › Recording) and VideoRecordingUITests (recordingAudioLine "Recording includes app audio.")
- [X] REC-004-T16 [US4] App unit tests (setting default and persistence, decision mapping from modes, status texts, coordinator early end) in Apps/projectM-iOS/Tests/RecordingAudioAppTests.swift — Verified 2026-11-14: RecordingAudioAppTests 9/9 (54 app tests in the run, 0 failures)
- [X] REC-004-T17 [US4] UI test toggling "Include microphone audio" and reading the status in Apps/projectM-iOS/UITests/RecordingAudioUITests.swift — Verified 2026-11-14: RecordingAudioUITests 1/1 (25 s warm)

## Phase 7: Polish

- [X] REC-004-T18 Privacy review in ADR-0053 (what reaches disk, when, for how long; REC-004-R10 evidence: no `AVPlayer`/`MPMusicPlayerController` playback path in Packages/CaptureKit or the app, by grep); repo checks (compliance, docs, motion, permission catalog, status events, script tests, privacy manifest, network symbols), type-check budget, package note in Packages/Compositor/Package.swift, spec status — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 OK; check_privacy_manifest and check_network_symbols OK on the Debug simulator app
- [ ] REC-004-T19 {device} Device stage: quickstart "Device" steps 1-4 on D1 (In-App Playback alignment within 40 ms, REC-004-S5; microphone consent; System/App Capture video only)

## Dependencies

T01 first (docs). T02, T03, T04 in parallel. US1 (T05-T08) needs T02-T03. US2 tests (T09) need T05-T06; T10-T11 are independent. US3 T12 needs T06; T13 needs T04, T06, T10. US4 needs T13. T18 last; T19 after merge.

## Parallel examples

- T02, T03, T04 (different packages and files).
- T10 and T11 beside T05-T08.

## Implementation strategy

MVP = US1 (owned audio in sync). Then consent (US2), system-capture exclusion and app wiring (US3), status UI (US4).
