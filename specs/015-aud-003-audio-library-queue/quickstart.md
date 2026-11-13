# Quickstart: validating AUD-003

## Package tests (host, any Mac)

```bash
swift test --package-path Packages/CaptureKit                          # incl. QueuePipelineTests (acceptance)
swift test --package-path Packages/CaptureKit -Xswiftc -DAUDIOCORE_NO_AVFAUDIO   # Linux approximation
swift test --package-path Packages/CaptureUI
```

Expected: `QueuePipelineTests` shows the counter stream of track A continuing across the reorder,
C following A, and a new queue over the same folder holding A, C, B with the current track.

## Simulator (iOS 27.2)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'id=<udid>' \
  -derivedDataPath .build/dd CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 -only-testing:projectM-iOSUITests/PlayQueueUITests
```

Expected: three imported tracks are reordered in the queue, the app is relaunched, the queue
lists the same order, nothing plays.

## Device (final phase, `{device}`)

On D1 with headphones: play three imported tracks, reorder while listening, listen for any gap;
add a second track while one track loops and confirm it ends once and the next follows; remove the
playing track; take a call during playback and reorder during it; confirm resume behavior is as
without the edit.
