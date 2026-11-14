# Quickstart: ANL-013 Stereo Correlation

```bash
# Package acceptance (host and Linux shape)
swift test --package-path Packages/AnalysisFeatures --filter StereoCorrelationTests
swift test --package-path Packages/AnalysisFeatures -Xswiftc -DANALYSIS_NO_ACCELERATE --filter StereoCorrelationTests
swift test --package-path Packages/ParameterGraph --filter "Correlation"

# App unit tests (own simulator)
xcodegen generate
xcodebuild build-for-testing -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,name=ANL13 iPhone 17' CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/AudioFeatureBindingAppTests \
  -only-testing:projectM-iOSTests/StereoPhaseWarningTests
```

Device check (open, `{device}`): play a track with one channel inverted (or wire a stereo interface
with one leg reversed) through Mix with a native visual and the performance overlay on: the overlay
reads a negative r, and after about a second the source status shows "Stereo channels look
phase-inverted"; switching AUD-009 to Left clears it about a second later.
