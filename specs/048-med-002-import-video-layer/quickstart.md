# Quickstart: MED-002 Import Video Layer

## Host and Linux shape (package)

```bash
swift test --package-path Packages/Compositor --filter 'Video'
swift test --package-path Packages/Compositor --scratch-path .build/linuxshape \
  -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
```

Expected: queue bound (`maxDepth ≤ 3`) through stall, jump and stop; frame-for-time exact over two
loops; late frames dropped; corrupt and over-limit fixtures refused with their typed error; the
remuxed copy has no audio track and no metadata; a solid frame reads back linear.

## Simulator (app)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,name=MED2 iPhone 17' \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/VideoLayerUITests \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180
```

`VideoLayerUITests` launches with `-uitestSeedVideo counter` (DEBUG only): choose Video, the frame
index advances, relaunch still plays, Remove Video falls back to "No video".

## Device (owner; `{device}` tasks)

On D1 and D3: pick a video from Photos (HEVC from the camera, an H.264 file) and from Files; a 4K60
clip and a long (≥ 10 min) file play; thermal state over 3 minutes of playback (D1, D3); Remove
Video; relaunch. Record results in `docs/test-reports/video-layer.md`.
