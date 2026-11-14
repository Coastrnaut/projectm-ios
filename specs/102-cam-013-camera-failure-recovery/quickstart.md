# Quickstart: CAM-013 Camera Failure Recovery

## Mac (simulator and host)

```bash
swift test --package-path Packages/Compositor --filter 'CameraRecoveryTests|CameraLayerTests'
# Linux shape of the rules (CPU only):
swift test --package-path Packages/Compositor --filter CameraRecoveryTests \
  -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,id=<udid>' CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests/CameraRecoveryTests -only-testing:projectM-iOSUITests/CameraRecoveryUITests
```

Expected: every reason clears the composite (zero camera pixels), shows its text and Retry; Retry
and the injected end bring pixels back; backoff 0, 2, 4, 8, 16, 30 s on the fake clock; denied at
start shows Open Settings without Retry.

## Device stage (`{device}`, D1 and D2; D3 for iPadOS 26)

1. Camera visual running; start a FaceTime call (or open the Camera app over Split View on D2):
   the picture clears at once, the notice says another app (or multitasking), the badge goes; end
   the call: the picture returns by itself. Tap Retry during the call: "Retrying…" spacing grows.
2. Settings › Privacy & Security › Camera › projectM-iOS off while the app runs: iOS ends the app;
   relaunch, choose Camera: the denied notice with Open Settings.
3. A warm device (system pressure) if it occurs: the pressure notice, return on recovery.
