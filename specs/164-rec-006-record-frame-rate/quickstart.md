# Quickstart: REC-006 Record frame rate

## Package (host, about 15 s)

```bash
swift test --package-path Packages/Compositor --filter 'FrameRecordingTests'
```

Expected: `RecordingRulesTests`, `RecordingFrameRateTests` and `RecordingFrameRateFixtureTests` pass;
the fixture prints one line per case (`REC-006 fixture 24fps 60Hz: frames=24 dropped=0 nominal=24.00`).

Linux shape: `swift build --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`.

## App (REC6 simulator, iOS 27.2)

```bash
xcodegen generate
xcodebuild build-for-testing -scheme projectM-iOS -destination 'platform=iOS Simulator,name=REC6 iPhone 17' ...
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/RecordingFrameRateAppTests \
  -only-testing:projectM-iOSUITests/RecordingFrameRateUITests
```

Expected: the app tests pass (persistence, availability with injected capabilities, Record fallback
notice, the last recording's rate and drops); the UI test selects 24 fps in under 30 s.

## Device (`{device}`, REC-006-S6)

On D1, select 24 fps, record 10 s of a projectM preset, and read the file back with the DEBUG probe
or `RecordedVideoInspector`: nominal 24 fps, times on the 1/24 s grid, the reported dropped count.
