# Quickstart: ANL-009 High Transient

```bash
swift test --package-path Packages/AnalysisFeatures --filter "HighTransient|MidTransient|KickDetector"
swift test --package-path Packages/AnalysisFeatures -Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path Packages/AnalysisFeatures/.build/linux --filter "HighTransient|MidTransient|KickDetector"
swift test --package-path Packages/ParameterGraph
swift test --package-path Packages/VisualGenerators
# App unit test on the row's simulator "ANL9 iPhone 17" (iOS 27.2):
xcodebuild build-for-testing / test-without-building -only-testing:projectM-iOSTests/AudioFeatureBindingAppTests
```

Binding in a scene: source ID `audio.highTransient` (0…1, envelope × confidence; at most 12 events
in any second). In an expression: `audio.highTransient`. It is a high-band transient, never a claim
that a hi-hat or cymbal played.
