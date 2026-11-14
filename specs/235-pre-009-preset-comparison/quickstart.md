# Quickstart: PRE-009 Preset Comparison

1. `xcrun simctl create "PRE9 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2`
2. Pure lockstep logic: `xcodebuild test` on the `Rendering` package, `-only-testing:RenderingTests/PresetComparisonTimelineTests`.
3. Acceptance (S1-S3): `ANGLERendering` package, `-only-testing:ANGLERenderingTests/PresetComparisonRunnerTests` (real engines off screen; asserts identical deliveries for A and B, with B slowed, and identical pixels for the same preset).
4. UI (S4): `xcodegen generate`, build-for-testing `projectM-iOS`, then `-only-testing:projectM-iOSUITests/PresetCompareUITests`.
5. Device (S5, `{device}`): on D1 open Compare with two presets for 60 s with music playing; note the previews' smoothness, the thermal state and the main visual resuming on Close.
