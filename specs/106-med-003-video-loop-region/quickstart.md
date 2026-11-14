# Quickstart: MED-003 Video Loop Region

## Mac (host and simulator)

```bash
swift test --package-path Packages/Compositor --filter 'VideoLoopTests|VideoPipelineTests|VideoLayerTests'
# Linux shape (CPU only):
swift test --package-path Packages/Compositor --filter 'VideoLoopTests|VideoPipelineTests' \
  -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
swift test --package-path Packages/SceneFormat --filter SceneVideoLoopTests
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,id=<udid>' CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests/VideoLoopTests -only-testing:projectM-iOSUITests/VideoLoopUITests \
  -only-testing:projectM-iOSUITests/VideoLayerUITests
```

Expected: every shown index inside the region across four boundaries; wrap out−1 → in; gap 0 with
the fake reader; recoveries counted; scene round trips; the UI test's indices stay inside.

## Device stage (`{device}`, D1)

1. Settings → Video → Choose from Photos: pick a clip of at least 10 s; set In ≈ 3 s, Out ≈ 6 s.
2. Watch at least five joints: no visible stall or flash; background and return: still inside.
3. Relaunch: the region is kept; Reset Loop: the whole clip loops.
