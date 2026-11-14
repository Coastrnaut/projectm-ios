# Tasks: QA-008 Recording Validation Suite

**Input**: `specs/163-qa-008-recording-validation/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the spec (QA-008-S1-S4). Budgets (owner rule 7): each unit test ~1-2 s, at
most 10 s; the corpus under 30 s; no wall-clock assertions.

## Phase 1: Foundational (blocks every story)

- [ ] QA-008-T01 Write the plain-Swift rules in `Packages/Compositor/Sources/FrameRecording/RecordingValidation.swift`: `RecordingExpectation` (defaults: allowedCodecs ["hvc1", "avc1"], frameRate 30, startTick 0, syncToleranceSeconds 0.020), `RecordingMeasurement`, `RecordingIssue` with the 17 codes of data-model.md, `RecordingValidationReport`, `checkTimestamps` and `evaluate` with research D6's precedence; no Apple imports (QA-008-R1-R10)
- [ ] QA-008-T02 [P] Write `RecordingValidationRulesTests.swift` in `Packages/Compositor/Tests/FrameRecordingTests/`: synthetic series for each timestamp code (including a single frame), duration and frame-count rules, precedence, and synthetic measurements for the faults no writer produces (`notIncreasing`, `firstTimeNotAtStart`, `audioFormat`, `audioNotContiguous`, `syncMarkerMissing`, `markerTimeMismatch`, `unexpectedMetadata`); Foundation and XCTest only (QA-008-S3)

## Phase 2: User Story 1 - Bad recordings fail CI (P1) MVP

**Independent test**: `swift test --package-path Packages/Compositor --filter RecordingValidationCorpusTests` — good fixtures pass, each bad fixture fails with exactly its code.

- [ ] QA-008-T03 [US1] Write the AVFoundation reader `Packages/Compositor/Sources/FrameRecording/RecordingValidator.swift`: `measure` (through `RecordedVideoInspector`, plus decoded audio sample count and breaks, metadata identifiers of the asset and its tracks), `markerTimes` (REC-004's flash and click finders, research D4), `validate` (QA-008-R2-R9)
- [ ] QA-008-T04 [P] [US1] Write the test fixture writer `Packages/Compositor/Tests/FrameRecordingTests/RecordingFixtureWriter.swift`: good files through `VideoFileWriter` with CPU-filled pixel buffers and LPCM chunks (flash frame, click, audio offset); raw AVAssetWriter files for a custom timescale, codec and metadata (research D2, D3)
- [ ] QA-008-T05 [US1] Write `RecordingValidationCorpusTests.swift`: 2 good fixtures and 11 bad fixtures (gap, duplicate, too long, too short, truncated, 24 fps against 30, audio +80 ms, audio missing, audio unexpected, Motion JPEG, location), each asserting `codes == [expected]`; plus `testExternalRecording` gated by `QA008_RECORDING` (QA-008-R11, R14; S1)
- [ ] QA-008-T06 [US1] Confirm CI runs the corpus before device steps: the Compositor package is in `build-and-test-apple`'s "Package tests (macOS host)" loop in `.github/workflows/ios-ci.yml`; record the corpus duration (QA-008-R12; S2)

## Phase 3: User Story 2 - Recorder tests use the validator (P1)

**Independent test**: `swift test --package-path Packages/Compositor --filter FrameRecordingTests` and `--filter CompositorRecordingTests` pass (GPU tests run on the Mac Studio).

- [ ] QA-008-T07 [US2] `RecordingAudioMuxTests.swift`: replace the private flash and click finders with `RecordingValidator.markerTimes`, and check the acceptance fixture with `validate` (audio expected, marker at 1.0 s, 20 ms) while keeping every existing assertion (QA-008-R13)
- [ ] QA-008-T08 [P] [US2] `MetalFrameRecorderTests.testLowStorageStopFinishesAPlayableFile` and `CompositorRecordingTests.testTenSecondFixtureDecodesWithMonotonicTimestamps`: add `validate` with the matching expectation (duration, no audio, no metadata) and keep the exact-times assertions (QA-008-R13)

## Phase 4: User Story 3 and 4 (P2, P3)

- [ ] QA-008-T09 [US3] Linux shape: CI's `host-tests-linux` runs the rules tests (the reader and corpus compile out); verify locally that the rules file and rules tests have no Apple imports (QA-008-R10)
- [ ] QA-008-T10 [US4] {device} Validate one recording exported from D1 with `testExternalRecording` (quickstart C) in the final QA phase

## Phase 5: Polish

- [ ] QA-008-T11 Package.swift comment, `docs/test-reports/recording-validation.md` (corpus, codes, durations), spec status
- [ ] QA-008-T12 Repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`); FrameRecording tests on simulator QA8 (iOS 27.2) through `xcodebuild -scheme Compositor`; type-check budget

## Dependencies

T01 → T02, T03 → T04 → T05 → T06; T03 → T07, T08; T01 → T09; T05 → T10. T02 ∥ T03; T04 ∥ T03 (different files); T07 ∥ T08.

## Implementation strategy

MVP = Phases 1-2 (the acceptance). Then the refactor (Phase 3), the Linux shape and docs.
