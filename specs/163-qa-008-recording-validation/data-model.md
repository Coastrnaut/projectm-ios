# Data Model: QA-008 Recording Validation Suite

All types are `Sendable, Equatable` plain Swift in `RecordingValidation.swift` (Linux-buildable).

## RecordingExpectation

| Field | Type | Default | Rule |
|---|---|---|---|
| allowedCodecs | [String] | ["hvc1", "avc1"] | R2 |
| frameRate | Int | 30 | interval = 600 / frameRate ticks |
| startTick | Int64 | 0 | R3 first time |
| durationSeconds | Double? | nil | R4 (±1 interval) |
| expectsAudio | Bool | false | R6 |
| audioSampleRate | Double | 44,100 | R6 |
| audioChannels | Int | 2 | R6 |
| checksSyncMarker | Bool | false | R7 |
| markerSeconds | Double? | nil | R7 flash time (±1 frame) |
| syncToleranceSeconds | Double | 0.020 | R7 (`RecordingAudioTimeline.toleranceSeconds`) |
| allowsMetadata | Bool | false | R8 |

## RecordingMeasurement

codec, width, height, presentationTicks [Int64] (1/600 s, file order), durationSeconds, audioTrackCount,
audioSampleRate?, audioChannels?, audioSampleCount, audioBreaks, flashSeconds?, clickSeconds?,
metadataIdentifiers [String]. `frameCount` = presentationTicks.count.

## RecordingIssue

`code` (`RecordingIssue.Code`) + `detail` (String). Codes (stable raw values):
`unreadable`, `codecNotAllowed`, `notIncreasing`, `duplicateTimestamp`, `timestampGap`,
`firstTimeNotAtStart`, `durationMismatch`, `frameCountMismatch`, `audioMissing`, `audioUnexpected`,
`audioFormat`, `audioNotContiguous`, `syncMarkerMissing`, `syncOutOfTolerance`, `markerTimeMismatch`,
`personalMetadata`, `unexpectedMetadata`.

## RecordingValidationReport

`measurement: RecordingMeasurement?` (nil when unreadable), `issues: [RecordingIssue]`, `passed`
(issues empty), `codes: Set<Code>`, `summary` (one line per issue).

## Personal metadata

An identifier is personal when its lowercased text contains any of: `location`, `iso6709`, `gps`,
`make`, `model`, `author`, `artist`, `creator`, `owner`, `user`, `phone`, `email`.
