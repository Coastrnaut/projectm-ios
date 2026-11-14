# Implementation Plan: QA-008 Recording Validation Suite

**Branch**: `feature/qa-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/163-qa-008-recording-validation/spec.md`

## Summary

One validator for recorded files, in REC-003's `FrameRecording` target, replaces the scattered
read-back assertions and is proven against a generated corpus of good and deliberately bad files:

1. `RecordingValidation.swift` (plain Swift, Linux-tested): `RecordingExpectation`,
   `RecordingMeasurement`, `RecordingIssue` (stable reason codes), `RecordingValidationReport` and the
   pure rules `RecordingValidation.evaluate(_:against:)`, including the timestamp-series checks
   (`checkTimestamps`).
2. `RecordingValidator.swift` (AVFoundation only): reads a file into a `RecordingMeasurement`
   (through `RecordedVideoInspector` for codec, size, times, duration and audio format; plus the
   decoded audio sample count and breaks, the flash/click marker times moved out of REC-004's test, and
   the metadata identifiers) and returns the report.
3. Tests: `RecordingValidationRulesTests` (synthetic series, Linux), `RecordingValidationCorpusTests`
   (generated good and bad files, macOS host, no GPU; plus the on-demand `testExternalRecording`), and
   the REC-003/004/015 tests switched to the validator.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio globals)

**Primary Dependencies**: none new; AVFoundation, CoreMedia, CoreVideo (Apple only, compiled out on
Linux)

**Storage**: fixtures in the temporary folder, deleted after each test; nothing committed

**Testing**: XCTest. Host: `swift test --package-path Packages/Compositor --filter RecordingValidation`
and `--filter FrameRecordingTests`. Linux shape: the rules file and the rules tests import nothing
from Apple (Foundation and XCTest only), and the reader and the corpus are behind
`#if canImport(AVFoundation)`; the Mac has no flag that removes AVFoundation, so CI's Linux job is the
proof (pending CI). iOS simulator QA8 (iOS 27.2) runs the FrameRecording tests through
`xcodebuild -scheme Compositor`.

**Target Platform**: macOS host (CI `build-and-test-apple`), iOS simulator, Linux (rules only)

**Project Type**: Swift package library + tests

**Performance Goals**: whole corpus under 30 s on the host; each fixture a few seconds at most

**Constraints**: no GPU needed by the corpus; no committed binaries; no wall-clock assertions

**Scale/Scope**: 2 source files, 2 new test files, 3 test files refactored, docs

## Constitution Check

- **I. Public Apple APIs only**: AVFoundation/CoreMedia public API only. Pass.
- **VI. Modular boundaries**: stays inside `FrameRecording`; no app, engine or capture import. Pass.
- **VII. Real-time audio safety**: test and debug code only; nothing on an audio callback. Pass.
- **X. Evidence-based quality**: the corpus proves the validator rejects each fault; device exports are
  checked only in the final phase and simulator results are not device evidence. Pass.
- **Privacy**: the validator enforces REC-003-R8 (no metadata) and flags location metadata. Pass.

No violations; no complexity tracking needed.

## Project Structure

```text
specs/163-qa-008-recording-validation/
├── spec.md  plan.md  research.md  data-model.md  quickstart.md  tasks.md
├── contracts/recording-validator.md
└── checklists/requirements.md

Packages/Compositor/
├── Package.swift                                   (comment only)
├── Sources/FrameRecording/
│   ├── RecordingValidation.swift                   (new, plain Swift)
│   ├── RecordingValidator.swift                    (new, AVFoundation)
│   └── RecordedVideoInspector.swift                (unchanged API)
└── Tests/
    ├── FrameRecordingTests/
    │   ├── RecordingValidationRulesTests.swift     (new, Linux)
    │   ├── RecordingValidationCorpusTests.swift    (new, macOS/iOS, no GPU)
    │   ├── RecordingFixtureWriter.swift            (new, test helper)
    │   ├── RecordingAudioMuxTests.swift            (uses the validator's marker finder)
    │   └── MetalFrameRecorderTests.swift           (REC-015 check via the validator)
    └── CompositorTests/CompositorRecordingTests.swift (REC-003 S1 via the validator)
```

**Structure Decision**: extend `FrameRecording`; no new target (research D1).
