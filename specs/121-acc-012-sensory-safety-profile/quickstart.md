# Quickstart: ACC-012 Sensory Safety Profile

## Package tests (host; FlashSafety also on Linux in CI)

```bash
swift test --package-path Packages/FlashSafety --filter SensorySafety
swift test --package-path Packages/VisualGenerators --filter SensorySafetyRender
```

Expected: the clamp table passes for every preset × parameter type; the GPU test reports 0 differing bytes
for Standard and Strict's measured rise within 0.10/s.

## App tests (own simulator)

```bash
xcrun simctl create "ACC12 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath .autonomous/derived-data-acc-012 \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests/SensorySafetyAppTests -only-testing:projectM-iOSUITests/SensorySafetyUITests
```

Expected: renderer inputs clamped (native host glow, bloom parameters, frame context, ANGLE and compositor
flash limits), persistence and backup round trip, Strict probe visible in under 30 s.

## Device (ACC-012-S6, `{device}`)

On D1: circular spectrum, glow on at 0.8 bound to Level; Settings → Sensory safety → Strict; the glow drops
to a quarter and stays there with loud music; on projectM with a bright preset, flashing is visibly slower.
