# Tasks: REC-016 Recording interruption recovery

**Input**: `specs/226-rec-016-recording-interruption-recovery/` (spec, plan, research, data-model, contracts/interruption-recovery.md, quickstart)
**Tests**: requested by the roadmap acceptance (injected writer failure) and the brief (start failure, background, thermal).

## Phase 1: Setup

- [X] REC-016-T01 Write ADR-0061 (fragmented writing, salvage of usable output, amends REC-003-R17 / ADR-0027) in docs/adr/0061-recording-fragmented-writing-and-salvage.md and list it in docs/adr/README.md — Verified 2026-11-14: ADR written and listed (0060 is the highest in the main checkout); validate_docs OK

## Phase 2: Foundational

- [X] REC-016-T02 Plain Swift in Packages/Compositor/Sources/FrameRecording/RecordingRecovery.swift (salvage outcome, thermal level, guard, notices); `RecordingStopReason.thermal`, `RecordingRefusal.thermal`, new writerFailed notice, `RecordedVideo.interruption` in RecordingOutcome.swift; fault kinds in RecordingStorage.swift; `fragmentIntervalSeconds` in RecordingSettings.swift — Verified 2026-11-14: RecordingThermalGuardTests (2 tests: guard rules, notices, DEBUG argument forms); Linux-shape build of Compositor with tests (-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE) OK
- [X] REC-016-T03 Writer: fragments, `salvage`, `forceFailureForTests`, ledger, fault sink kinds (VideoFileWriter.swift) (contract C1) — Verified 2026-11-14: RecordingRecoveryTests (append/writer/finish kinds through the real writer); mutation without movieFragmentInterval makes the writer and finish tests fail (file unreadable, deleted)
- [X] REC-016-T04 Recorder: salvage path with read-back, start-failure cleanup, texture-cache flush, ledger (MetalFrameRecorder.swift) (contract C2) — Verified 2026-11-14: RecordingRecoveryTests ledger and framesInFlight asserts; existing FrameRecording suite 150 tests, 0 failures, 1 skip (host, 41.8 s)

## Phase 3: User Story 1 - A writer failure keeps what was recorded (P1) MVP

- [X] REC-016-T05 [US1] Package tests RecordingRecoveryTests.swift: append, writer and finish failures in a 2 s 64×48 fixture → ledger at baseline, nothing in flight, kept file read back within one fragment; early writer failure → nothing kept; an out-of-storage fault still deletes the file (REC-016-R9); normal finish has no `moof` and passes QA-008 (REC-016-S1, S5) — Verified 2026-11-14: RecordingRecoveryTests 7/7 on the host (5.8 s): append keeps 30/30, writer and finish keep the completed fragments within one fragment + 0.5 s of 45, early failure and out of storage keep nothing, normal finish has no moof and passes RecordingValidator
- [X] REC-016-T06 [US1] Coordinator: kept part offered with the X13 notice; StatusEvents rows (VideoRecordingCoordinator.swift, StatusEvents.swift) (contract C3.1, C4) — Verified 2026-11-14: RecordingRecoveryAppTests (notice, offered, lastStopReason .writerFailed; StatusEventCatalog.recordingNotice → X13); StatusEventsTests 8/8; check_status_events OK
- [X] REC-016-T07 [US1] App tests RecordingRecoveryAppTests.swift: append failure mid-recording → idle, tap detached, recorder released (ledger), notice, offered file read back with the frames before the failure — Verified 2026-11-14: RecordingRecoveryAppTests.testInjectedWriterFailureReleasesResourcesAndOffersTheKeptPart (REC16 iOS 27.2 simulator): idle, tap detached, holdsRecorder false, ledger back to baseline, offered file reads back 10 frames with strictly increasing times, Record works again

## Phase 4: User Story 2 - A failed start leaves nothing behind (P1)

- [X] REC-016-T08 [US2] Package test (start failure → no file, ledger at baseline) and app test (folder empty, idle, notice) (REC-016-S2) — Verified 2026-11-14: RecordingRecoveryTests.testStartFailureLeavesNothing (host and simulator) and RecordingRecoveryAppTests.testInjectedStartFailureLeavesNothingOnDisk (folder empty, idle, notice)

## Phase 5: User Story 3 - Leaving the app finishes the file (P1)

- [X] REC-016-T09 [US3] App test: background stop offers a finished, readable file with the background notice (REC-016-S3) — Verified 2026-11-14: RecordingRecoveryAppTests.testBackgroundStopFinishesAndOffersTheFile (offered, background notice, read back = recorded frames); VideoRecordingAppTests 18/18

## Phase 6: User Story 4 - The device gets hot (P2)

- [X] REC-016-T10 [US4] Thermal guard in the coordinator (injected level, DEBUG `-uitestThermalState`) and its tests: guard rules (package), Serious warns once, Critical stops and offers, Record at Critical refused (app) (REC-016-S4) — Verified 2026-11-14: RecordingThermalGuardTests (host) and RecordingRecoveryAppTests.testThermalWarningAndStop, testThermalStateMapping (refusal X12, one warning X13, Critical stop .thermal offered)

## Phase 7: Polish

- [X] REC-016-T11 DEBUG `-uitestWriterFault` and UI test RecordingRecoveryUITests.swift (append failure → panel offers the part, probe reads video, < 30 s) — Verified 2026-11-14: RecordingRecoveryUITests.testWriterFailureOffersThePartRecordedBeforeIt passed in 9.8 s and 11.8 s (REC16 iOS 27.2): panel, notice, probe frames=10; RecordingDiskGuardUITests 2/2
- [X] REC-016-T12 Linux-shape build of Compositor; existing FrameRecording, REC-003/REC-015/StatusEvents app suites; repo checks; privacy manifest and network symbols; type-check budget flags — Verified 2026-11-14: Linux-shape swift build --build-tests of Compositor OK; FrameRecording 150 tests (1 skip) host 16.7 s; RecordingRecoveryTests 7/7 and MetalFrameRecorderTests on the iOS 27.2 simulator; app suites (Recording*, VideoRecording, StatusEvents, PhotosSave, CacheCleanup) 101 tests 0 failures; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 174 OK; check_privacy_manifest and check_network_symbols OK on the Debug app; type-check flags: no warning in touched files
- [ ] REC-016-T13 {device} On D1 record 30 s (normal finish plays, no `moof`), and a Debug run with `-uitestWriterFault writer:90` keeps a playable part; note CPU against REC-003 Writer-fault part automated on D1 2026-11-15 (docs/test-reports/qa-011/acceptance/D1-B03.md): RecordingRecoveryUITests, a writer failure offers the part recorded before it. Open: a 30 s normal recording (no moof) and CPU against REC-003.

## Dependencies

T01 → T02 → T03 → T04 → T05 ; T04 → T06 → T07, T08, T09 ; T02 → T10 ; T06 → T11 ; all → T12.

## Implementation Strategy

MVP = Phases 1-3. Then start failure, background proof, thermal, the UI test and polish.

## Analysis (speckit-analyze, 2026-11-14)

Applied: R9 (out-of-storage unchanged) given an explicit case in T05 besides the existing REC-015 suites in T12; T07 names the
coordinator-side release checks of R4 (tap detached, no recorder). Coverage: R1 T03, T05; R2 T02, T03, T11; R3 T04, T05;
R4 T04, T05, T07; R5 T06, T07; R6 T04, T08; R7 T09; R8 T02, T10; R9 T05, T12. S1-S5 map to T05, T08, T09, T10, T05. No
constitution conflict (public AVFoundation API, nothing stored, no network). Terminology: "kept part" = salvaged file
throughout.
