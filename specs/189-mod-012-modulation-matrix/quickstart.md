# Quickstart: MOD-012 Modulation Matrix UI

```bash
swift test --package-path Packages/ParameterGraph --filter ModulationMatrixTests
swift test --package-path Packages/SceneFormat --filter SceneBindingEnabledTests
# app (private simulator "MOD12 iPhone 17", iOS 27.2):
xcodebuild build-for-testing -scheme projectM-iOS -destination 'platform=iOS Simulator,name=MOD12 iPhone 17' ...
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/ModulationMatrixAppTests \
  -only-testing:projectM-iOSUITests/ModulationMatrixUITests
```

Manual check (simulator): launch with `-uitestSeedModulationMatrix`, open Settings → Modulation: two
destinations (Glow Intensity with two layers, Glow Radius with one); turn layer 2 off: the probe shows the
intensity 0.6000 instead of 0.3000 and the radius stays 0.0400; Undo restores it.
