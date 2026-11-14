# Quickstart: REC-009 Recording status overlay

## Package tests (Mac host)

```bash
swift test --package-path Packages/Compositor --filter RecordingStatusSummaryTests
```

## App unit tests and UI test (simulator "REC9")

```bash
xcodegen generate
xcodebuild build-for-testing -scheme projectM-iOS -destination "platform=iOS Simulator,name=REC9 iPhone 17" ...
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/RecordingStatusOverlayAppTests
xcodebuild test-without-building ... -only-testing:projectM-iOSUITests/RecordingStatusOverlayUITests
```

Expected: the exclusion test reads every recorded frame back as the visual's red with no probe green;
the UI test finds the indicator, "Dropped frames: 0" and a "… free, about … min left" line.

## Device `{device}`

On D1, record the Photo visual and look at the lines; on a nearly full device see the low warning (the
Debug `-uitestStorage` values jump straight below the guard's stop threshold, so they show the stop, not the warning); save the file and confirm the lines are not in it.
