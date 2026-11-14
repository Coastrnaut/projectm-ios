# Quickstart: ANL-015 Section Energy Change

```bash
# Package acceptance (host and Linux shape)
swift test --package-path Packages/AnalysisFeatures --filter SectionEnergyChangeTests
swift test --package-path Packages/AnalysisFeatures -Xswiftc -DANALYSIS_NO_ACCELERATE --filter SectionEnergyChangeTests
swift test --package-path Packages/ParameterGraph --filter "SectionChange"

# App unit tests (own simulator)
xcodegen generate
xcodebuild build-for-testing -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,name=ANL15 iPhone 17' CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/AudioFeatureBindingAppTests
```

Acceptance: `SectionEnergyChangeTests.testQuietToLoudFiresOnceAfterDwell` — 4 s at −40 dBFS then 6 s
at −10 dBFS gives exactly one rising change whose confirming frame ends within
[step + 88,200, step + 88,200 + 2,048] samples.

Device check (open, `{device}`): with a native visual and a binding from "Section change" to the
glow, play a track with a clear quiet intro and a loud chorus: the glow flashes once about 2 s after
the chorus starts and not on individual drum hits.
