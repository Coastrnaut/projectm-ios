# Quickstart: ANL-008 Mid Transient

```bash
swift test --package-path Packages/AnalysisFeatures --filter "MidTransient|KickDetector"
swift test --package-path Packages/AnalysisFeatures -Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path Packages/AnalysisFeatures/.build/linux --filter "MidTransient|KickDetector"
swift test --package-path Packages/ParameterGraph
swift test --package-path Packages/VisualGenerators
# App unit test on the row's simulator "ANL8 iPhone 17" (iOS 27.2):
xcodebuild build-for-testing / test-without-building -only-testing:projectM-iOSTests/AudioFeatureBindingAppTests
```

Binding in a scene: source ID `audio.midTransient` (0…1, envelope × confidence). In an expression:
`audio.midTransient`. It is a mid-band transient, never a claim that a snare played.
