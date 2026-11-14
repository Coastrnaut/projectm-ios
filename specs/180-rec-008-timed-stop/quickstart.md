# Quickstart: REC-008 Timed recording stop

## Package acceptance (Mac host, GPU)

```bash
swift test --package-path Packages/Compositor --filter RecordingTimedStopTests
swift test --package-path Packages/Compositor --filter RecordingAudioTimelineTests
```

Expected: every case passes; each 10 s fixture prints its frames, duration and audio end.

## App unit tests and UI test (simulator "REC8")

```bash
xcodegen generate
xcodebuild build-for-testing -scheme projectM-iOS -destination "platform=iOS Simulator,name=REC8 iPhone 17" ...
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/RecordingTimedStopAppTests
xcodebuild test-without-building ... -only-testing:projectM-iOSUITests/RecordingTimedStopUITests
```

Expected: the UI test sets 10 s by launch argument, records on the Photo visual, and the probe reads a
finished file of 10.00 s.

## Device `{device}`

On D1, set Stop recording after → 10 seconds, record the Photo visual, Save, and check the file with
`RecordingValidator` (duration 10 s, 300 frames at 30 fps).
