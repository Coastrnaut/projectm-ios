# Quickstart: PRE-001 Visual Thumbnail Cache

## Package (any OS)

```bash
swift test --package-path Packages/PresetLibrary --filter PresetThumbnail
```

Expect: the acceptance (first pass renders N, second renders 0 with the same IDs and files), relaunch,
the four migration fixtures, cancellation, queue bound, determinism. On Linux the same suite runs in CI.

## App on the own simulator ("PRE1 iPhone 17", iOS 27.2)

```bash
xcodegen generate
xcodebuild build-for-testing -scheme projectM-iOS -destination "platform=iOS Simulator,name=PRE1 iPhone 17" \
  -derivedDataPath .autonomous/derived-data-pre-001 CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/PresetThumbnailModelTests \
  -only-testing:projectM-iOSUITests/PresetThumbnailUITests
```

Expect: `PresetThumbnailUITests` opens Included and finds `thumbnail:<name>` images for the first rows
(< 30 s). Simulator runs are not evidence of performance.

## Device (`{device}`, D1)

Open the browser over a running visualizer, scroll Included and a pack so about 20 thumbnails generate,
and compare the frame meter with a run where the thumbnails are already cached (S7: within 10%).
