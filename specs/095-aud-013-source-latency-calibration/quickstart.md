# Quickstart: AUD-013 Source Latency Calibration

1. Package tests: `swift test --package-path Packages/AudioCore --filter LatencyOffset`, the same
   with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO` (Linux shape), and
   `swift test --package-path Packages/AnalysisFeatures --filter LatencyOffsetAcceptance` (prints
   the measured shift per offset).
2. App: `xcodegen generate`, then `xcodebuild test` on the feature simulator with
   `-only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/LatencyOffsetUITests` (plus
   NativeVisualUITests, SourceSwitchUITests, InputTrimUITests as regression).
3. Manual on a device (`{device}`, AUD-013-T15): In-App Playback with Bluetooth headphones; tap
   Estimate from Output, compare the visuals with the beat; then measure the click-to-flash delay
   with a 240 fps camera at 0 ms and at the estimate.
