# Quickstart: OSC-003 OSC Parameter Routes

```bash
swift test --package-path Packages/PerformanceControl --filter "OSCParameterRoutesTests|ExternalLiveValuesTests"
xcodegen generate
xcodebuild build-for-testing -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'platform=iOS Simulator,name=<sim>' CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/OSCRoutesCoordinatorTests -only-testing:projectM-iOSUITests/OSCRoutesUITests
```

Manual (device, optional): turn OSC on, send `/projectm/param/glow.intensity 0.25` from a controller on
the same Wi-Fi with the Circular Spectrum glow on; the glow dims. Send `/projectm/unknown 1`; Settings ›
OSC › OSC Routes shows "Ignored addresses 1".
