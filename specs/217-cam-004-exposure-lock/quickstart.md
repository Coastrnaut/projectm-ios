# Quickstart: CAM-004 Camera Exposure Lock

## Mac (stand-in camera)

```bash
swift test --package-path Packages/Compositor --filter CameraExposureTests
xcodegen generate
# app tests and the UI test on the feature's own simulator (iOS 27.2):
xcodebuild build-for-testing -scheme projectM-iOS -destination 'platform=iOS Simulator,name=CAM4 iPhone 17' ...
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/CameraExposureAppTests \
  -only-testing:projectM-iOSUITests/CameraExposureUITests
```

Expected: lock → `locked`, unlock → `continuousAuto`; unsupported → explanation, 0 configurations;
lens switch while locked releases the previous lens's device.

## Device (D1, `{device}` CAM-004-T08)

1. Choose the Camera visual (Back, Wide), allow the camera.
2. Settings › Camera › Lock exposure on; point the camera from a bright window to a dark corner:
   the picture brightness stays. Off: it adapts again.
3. Lock, switch to Ultra Wide: the switch shows off; the picture adapts.
4. Lock, choose another visual and return to Camera: the switch is off.
