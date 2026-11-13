# Quickstart: REC-012 Share via Files

## Simulator (any Mac with the pinned Xcode)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath .autonomous/derived-data-rec-012 \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/CaptureShareUITests \
  -only-testing:projectM-iOSUITests/FrameCaptureUITests -only-testing:projectM-iOSUITests/VideoRecordingUITests
```

Expected: `CaptureShareAppTests` pass (lifecycle, sweep, names, excluded types); `CaptureShareUITests`
passes under 30 s: frame → Share… → simulated cancel → `frame=yes copies=0`; recording → Share… →
simulated completion → `recording=yes copies=0` and "Shared.".

## Device D1 (owner, `{device}`)

1. Photo or Circular Spectrum visual; Save Frame → PNG; the "Frame ready" panel appears.
2. Share… → AirDrop to a nearby device: the file arrives as "Visualizer Frame <date> at <time>.png";
   the panel is still there.
3. Share… → Messages: the picture is attached; cancel the message; the panel is still there.
4. Share… → Save to Files → On My iPhone; the file is there; Discard removes the panel.
5. Record ~5 s, Stop; "Recording ready"; Share… → Save to Files; the MP4 plays in Files.
6. Share… → close the sheet: the panel stays; Save… still saves the same recording.
7. The sheet shows no "Save Image"/"Save Video" and no "Assign to Contact"; no permission prompt
   appears.
