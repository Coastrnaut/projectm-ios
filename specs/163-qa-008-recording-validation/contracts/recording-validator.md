# Contract: RecordingValidator (QA-008)

```swift
// Plain Swift (Linux)
public enum RecordingValidation {
    /// R3: issues of a 1/600 s time series (file order).
    public static func checkTimestamps(_ ticks: [Int64], frameRate: Int, startTick: Int64) -> [RecordingIssue]
    /// R2-R8 with the precedence of research D6.
    public static func evaluate(_ m: RecordingMeasurement, against e: RecordingExpectation) -> RecordingValidationReport
    /// Unreadable file.
    public static func unreadable(_ detail: String) -> RecordingValidationReport
}

// AVFoundation only
public enum RecordingValidator {
    public static func measure(_ url: URL, expectation: RecordingExpectation) async -> RecordingMeasurement?
    public static func validate(_ url: URL, expectation: RecordingExpectation) async -> RecordingValidationReport
    /// REC-004 marker finder: first bright frame, first loud sample (seconds), nil when not found.
    public static func markerTimes(_ url: URL) async -> (flash: Double?, click: Double?)
}
```

## Rules (per issue code)

| Code | Fires when |
|---|---|
| unreadable | no readable video track (alone) |
| codecNotAllowed | codec ∉ allowedCodecs |
| notIncreasing | a time below the previous one |
| duplicateTimestamp | a time equal to the previous one |
| timestampGap | an interval > 1.5 × frame interval |
| firstTimeNotAtStart | first time ≠ startTick (±1 tick) |
| durationMismatch | \|duration − (last + interval)\| > interval, or \|duration − expected\| > interval |
| frameCountMismatch | \|frames − duration × fps\| > 1, only if no timestamp or duration issue |
| audioMissing / audioUnexpected | audio track count vs expectsAudio |
| audioFormat | sample rate or channels differ (only when audio expected and present) |
| audioNotContiguous | sample count 0 or any break |
| syncMarkerMissing | marker checked and flash or click not found |
| syncOutOfTolerance | \|click − flash\| > tolerance |
| markerTimeMismatch | markerSeconds given and \|flash − markerSeconds\| > 1 frame interval |
| personalMetadata | an identifier matches the personal list |
| unexpectedMetadata | any other metadata item when allowsMetadata is false |
