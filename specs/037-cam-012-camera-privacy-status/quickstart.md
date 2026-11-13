# Quickstart: CAM-012 Camera Privacy Status

## Simulator (stand-in camera)

```bash
xcodegen generate
xcrun simctl create "CAM12 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath .autonomous/derived-data-cam-012 \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests/CameraPrivacyStatusTests \
  -only-testing:projectM-iOSUITests/CameraPrivacyStatusUITests -only-testing:projectM-iOSUITests/CameraUITests
```

Expected: the indicator tests and the no-freeze frame-loop test pass; the UI test shows the badge
after choosing Camera, removes it on Stop camera, shows the circular spectrum (the visual chosen
before Camera), keeps `sourceStarts` at 1 and the controls respond.

## Device (CAM-012-S5, `{device}`, owner)

1. Install a Debug build on D1 (iPhone 15). Start In-App Playback.
2. Settings › Visual › Camera; allow camera access if asked. iOS's green camera dot and the app's
   "Camera on" badge appear.
3. Tap **Stop camera** on the badge. Expected: the badge disappears at once, iOS's camera dot turns
   off within a second, the previous visual animates, and the music keeps playing.
4. Pause and resume, lock and unlock: the camera stays off until Camera is chosen again.
