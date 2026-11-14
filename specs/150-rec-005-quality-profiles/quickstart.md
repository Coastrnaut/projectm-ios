# Quickstart: REC-005 Record quality profiles

## A. Package (Mac host)

```bash
swift test --package-path Packages/Compositor --filter 'RecordingQuality|RecordingStorage|MetalFrameRecorder'
```

Expect: every profile available on the host records a 2 s noise fixture that reads back with its
codec, exact size, frame rate ±1 and bit rate ±25% (`RecordingQualityFixtureTests`); injected "no
HEVC" and "at most 1920" disable exactly High and Max with reasons; Standard's output settings equal
today's.

## B. App (simulator "REC5 iPhone 17", iOS 27.2)

```bash
xcodegen generate
# build-for-testing, then:
-only-testing:projectM-iOSTests/RecordingQualityAppTests -only-testing:projectM-iOSUITests/RecordingQualityUITests
```

Expect: the setting defaults to Standard and persists; Record with an injected "no HEVC" source and
Max selected records with Standard and shows "Recording at Standard: …"; the picker UI test selects
High in under 30 s.

## C. Device `{device}`

On D1 (and D2), record 5 s in each available profile and read each file back
(`RecordedVideoInspector` through the DEBUG probe): codec, size, frame rate and bit rate as in the
contract table. Not simulator evidence.
