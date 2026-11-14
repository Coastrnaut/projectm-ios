# QA-008 Recording validation suite — test report

Spec: `specs/163-qa-008-recording-validation/`. Code: `Packages/Compositor/Sources/FrameRecording/`
(`RecordingValidation.swift`: plain-Swift rules; `RecordingValidator.swift`: AVFoundation reader).

## What runs where

| Suite | Where | Needs |
|---|---|---|
| `RecordingValidationRulesTests` (15) | Linux, macOS host, iOS simulator | nothing (synthetic series and measurements) |
| `RecordingValidationCorpusTests` (13 + 1 on demand) | macOS host (CI `build-and-test-apple`, "Package tests (macOS host)"), iOS simulator | AVFoundation; no GPU |
| REC-003/004/015 read-back tests, now through the validator | macOS host with a Metal device (skipped without one) | Metal |

CI runs the Compositor package tests on the macOS host on every push, so a bad file fails CI long
before the final device phase (QA-008-S2).

## Corpus (generated at test time, deleted after each test; nothing committed)

| Fixture | Made with | Expected codes |
|---|---|---|
| 1 s video only, 30 fps | `VideoFileWriter` (app settings) | none |
| 1.5 s, owned audio, flash at 1.0 s, click at 1.0 s | `VideoFileWriter` + LPCM chunks | none |
| frames 10-12 missing | `VideoFileWriter` | `timestampGap` |
| one frame 1/90,000 s after the previous | AVAssetWriter, timescale 90,000 | `duplicateTimestamp` |
| 30 frames in a 2 s file | `VideoFileWriter` | `durationMismatch` |
| 1 s file, 2 s expected | `VideoFileWriter` | `durationMismatch` |
| first 60 % of a good file's bytes | file copy | `unreadable` |
| 24 frames at 24 fps, checked at 30 fps (passes at 24) | `VideoFileWriter` | `frameCountMismatch` |
| click 80 ms after the flash | `VideoFileWriter` | `syncOutOfTolerance` |
| no audio track, audio expected | `VideoFileWriter` | `audioMissing` |
| audio track, none expected | `VideoFileWriter` | `audioUnexpected` |
| Motion JPEG (on the iOS simulator, which has no Motion JPEG encoder: H.264 against an HEVC-only allow-list) | AVAssetWriter | `codecNotAllowed` |
| QuickTime location item (reads back as `uiso/loci`, common key `location`) | AVAssetWriter | `personalMetadata` |

Faults no writer produces (`notIncreasing`, `firstTimeNotAtStart`, `audioFormat`, `audioNotContiguous`,
`syncMarkerMissing`, `markerTimeMismatch`, `unexpectedMetadata`) are covered by the rules tests.

## Results, 2026-11-14 (Mac Studio, Xcode 27.2, macOS host)

- `swift test --package-path Packages/Compositor --filter "FrameRecordingTests|CompositorRecordingTests"`:
  81 tests, 0 failures, 1 skipped (`testExternalRecording`), 3.7 s of test time. The corpus took
  0.96-1.27 s for 13 files (0.05-0.41 s each). No function body over 300 ms or expression over 150 ms
  to type-check.
- iOS 27.2 simulator QA8 (`xcodebuild -scheme Compositor` build-for-testing, then test-without-building
  `-only-testing:FrameRecordingTests -only-testing:CompositorTests/CompositorRecordingTests`): 81 tests,
  0 failures, 1 skipped, 5.5 s; the corpus 1.5 s. Simulator results are not device evidence.
- The on-demand check (`QA008_RECORDING=<file> ... --filter testExternalRecording`) on a scratch H.264
  file written with frame reordering and a location item printed `FAIL` with `firstTimeNotAtStart`,
  `timestampGap`, `notIncreasing` and `personalMetadata`, as expected.
- Linux shape: `RecordingValidation.swift` type-checks alone with `RecordingSettings.swift` and
  `RecordingAudioTimeline.swift` (no Foundation); the rules tests import only XCTest. CI's Linux job
  is the full proof (pending CI).

## Findings

- `VideoFileWriter` in its offline mode (`realTime: false`) with both video and audio inputs fed from
  one thread stalls the video input after about 1.2 s (each append then waits its 5 s limit and
  reports `notReady`). The app records live (`realTime: true`), where this does not happen, and REC-004's
  tests also record live; the fixtures therefore use live mode with a 1 ms retry. Offline recording
  with audio is not used by the app today; a future offline export with audio would need the writer
  to feed its inputs with `requestMediaDataWhenReady`.
