# Quickstart: CAM-002 Front Camera Layer

## Mac (simulator and host; never device evidence)

```bash
swift test --package-path Packages/Compositor --filter 'CameraGeometryTests|CameraLayerTests'
xcodegen generate
# own simulator: xcrun simctl create "CAM2 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination "id=<udid>" \
  -derivedDataPath .autonomous/derived-data-cam-002 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/FrontCameraUITests \
  -only-testing:projectM-iOSUITests/CameraUITests -only-testing:projectM-iOSUITests/PermissionAuditUITests
python3 scripts/check_permission_catalog.py && python3 scripts/check_compliance.py && python3 scripts/validate_docs.py
python3 scripts/check_motion_policy.py && python3 scripts/test_scripts.py
```

Expected: the mirror matrix (4 position/mirror combinations × 4 turns) passes; the marker test
finds the marker on the same side in the composite, the REC-001 capture and the REC-003 output
pass for mirror on and off; the UI test sees "Front camera on" and the Mirror value change.

## Device stage (`{device}`, D1-D3, a person)

1. Choose Camera, then Front. The picture is upright and mirrored (raise your right hand: the
   picture's right side moves); the badge reads "Front camera on"; iOS's green dot shows.
2. Rotate to landscape and back: upright, filled, still mirrored.
3. Turn Mirror off: the picture flips at once. Save Frame and Record a few seconds with Mirror on
   and off; the saved picture and video match the screen.
4. Switch Back ↔ Front a few times: the new camera within 2 s, never a frame of the old camera,
   audio uninterrupted (CAM-002-S7).
