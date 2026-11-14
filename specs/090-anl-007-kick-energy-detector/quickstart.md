# Quickstart: ANL-007 Kick Energy Detector

Run from the repository root.

```bash
# Package acceptance (host, then the Linux shape)
swift test --package-path Packages/AnalysisFeatures --filter KickDetectorTests
swift test --package-path Packages/AnalysisFeatures -Xswiftc -DANALYSIS_NO_ACCELERATE \
  --scratch-path Packages/AnalysisFeatures/.build/linux --filter KickDetectorTests
# Whole suites touched
swift test --package-path Packages/AnalysisFeatures
swift test --package-path Packages/ParameterGraph
swift test --package-path Packages/PerformanceControl
swift test --package-path Packages/VisualGenerators
# App unit tests on the row's own simulator
xcrun simctl create "ANL7 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,name=ANL7 iPhone 17' -only-testing:projectM-iOSTests \
  -derivedDataPath .autonomous/derived-data-anl-007 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180
xcrun simctl delete "ANL7 iPhone 17"
```

Expected (see spec Success Criteria): the low pulse train fires once per pulse; high, mid,
sustained bass (after its start), silence, dither and white noise never fire; −30 and −6 dBFS give
identical positions; the pipeline publishes `.transient(band: .kick, …)` events and frames with a
decaying `kickEnvelope`; `audio.kick` binds and drives the glow in the app. KickDetectorTests take
well under 1 s together.
