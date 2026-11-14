# Quickstart: QA-008 Recording Validation Suite

## A. Rules on any host (Linux included)

```bash
swift test --package-path Packages/Compositor --filter RecordingValidationRulesTests
```

Expected: all pass; synthetic series cover each timestamp code, the precedence rules and the verdict.

## B. Corpus on the macOS host (what CI runs in `build-and-test-apple`)

```bash
swift test --package-path Packages/Compositor --filter RecordingValidationCorpusTests
```

Expected: the good fixtures pass; each bad fixture fails with exactly its code (gap → `timestampGap`,
duplicate → `duplicateTimestamp`, too long / too short → `durationMismatch`, truncated → `unreadable`,
24 fps against 30 → `frameCountMismatch`, audio 80 ms late → `syncOutOfTolerance`, no audio →
`audioMissing`, audio when none expected → `audioUnexpected`, Motion JPEG → `codecNotAllowed`,
location → `personalMetadata`). Whole suite under 30 s.

## C. A device export (final phase, `{device}`)

Copy the recording from the device (Files app or `devicectl device copy from`), then:

```bash
QA008_RECORDING=/path/to/recording.mp4 QA008_EXPECT_AUDIO=0 QA008_FPS=30 \
  swift test --package-path Packages/Compositor --filter testExternalRecording
```

Optional: `QA008_MARKER_SECONDS=<s>` when the recording shows a flash and plays a click together
(checks A/V sync within 20 ms). The test prints the report and fails on any issue. Without
`QA008_RECORDING` it is skipped.
