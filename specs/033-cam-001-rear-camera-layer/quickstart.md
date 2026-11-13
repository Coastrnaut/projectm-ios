# Quickstart: validating CAM-001

## Package (Mac host, simulator, Linux shape)

```bash
swift test --package-path Packages/Compositor --filter Camera
swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL \
  -Xswiftc -DANALYSIS_NO_ACCELERATE --filter Camera       # CPU tests only
```

Expected: the solid stub color reads back as its linear value; the striped stub shows only its
middle stripe in a square output; every scenario maps to the documented state and the fallback;
stop drops the picture.

## App (iOS 27.2 simulator, own simulator, unsigned)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,id=<CAM simulator>' -derivedDataPath .autonomous/derived-data-cam-001 \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/CameraUITests
```

Expected: `CameraVisualTests` (lifecycle, persistence, states) and `CameraUITests` (denied notice,
app usable; granted frames counted) pass. Simulator results are never device evidence.

## Device stage (last; `{device}` tasks in tasks.md)

On D1, D2, D3 with a Debug build: choose Camera → iOS prompt → Allow → live upright picture under the
spectrum and the green camera indicator; Don't Allow → notice + Open Settings; revoke in Settings
while backgrounded → notice on return; open the Camera app in Split View or take a call → paused
notice, picture returns after; rotate; 3 minutes running with the thermal state recorded; choose
another visual / pause / background → the indicator goes off.
