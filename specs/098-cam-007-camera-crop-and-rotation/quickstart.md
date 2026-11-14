# Quickstart: CAM-007 Camera Crop and Rotation

## Mac (simulator and host; never device evidence)

```bash
swift test --package-path Packages/Compositor --filter 'CameraCropTests|CameraGeometryTests|CameraMirrorTests|CameraLayerTests'
# Linux shape of the CPU geometry:
swift test --package-path Packages/Compositor --filter 'CameraCropTests|CameraGeometryTests|CameraMirrorTests' \
  -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
xcodegen generate
# own simulator: xcrun simctl create "CAM7 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination "id=<udid>" \
  -derivedDataPath .autonomous/derived-data-cam-007 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/CameraCropUITests \
  -only-testing:projectM-iOSUITests/CameraUITests -only-testing:projectM-iOSUITests/FrontCameraUITests
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py && python3 scripts/check_motion_policy.py
python3 scripts/check_permission_catalog.py && python3 scripts/test_scripts.py
python3 scripts/check_privacy_manifest.py <built Debug .app>
```

Expected: the geometry table (2 picture sizes × 4 turns × mirror × 3 output shapes × every crop)
holds every guarantee of [contracts/camera-crop.md](contracts/camera-crop.md); the pixel tests
find the marker picture's center lines at the predicted relative positions at portrait and
landscape sizes for Fill and Fit; the UI test sees the Crop, Anchor and Zoom values change.

## Device stage (`{device}`, D1-D3, a person)

1. Choose Camera (Back). Fill, Center, 1×: rotate portrait → landscape → portrait; the picture
   fills, is upright and undistorted, centered.
2. Fill, Top, 2×: point the camera at a doorframe top; rotate; the top of the picture stays at the
   top of the screen, twice the plain fill size.
3. Fit: the whole picture is visible with black bars in both orientations.
4. Repeat 1-3 with Front (mirrored). Save Frame in each mode; the saved picture matches the screen
   (CAM-007-S6).
