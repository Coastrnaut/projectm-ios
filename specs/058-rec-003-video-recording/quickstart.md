# Quickstart: validating REC-003 Video Recording

Contract: [contracts/video-recording.md](contracts/video-recording.md). Owner rule 7 budgets: unit
tests ~1-2 s (≤ 10 s), suites < 1 min, the UI test < 30 s. Never use the Simulator panel tool.

## A. Package (Mac host and Linux shape)

```bash
swift test --package-path Packages/Compositor --filter 'FrameRecordingTests|CompositorRecordingTests'
swift test --package-path Packages/Compositor --scratch-path .build/linuxshape \
  -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE \
  --filter FrameRecordingTests
```

Expected: the 10-second fixture (160 × 120, simulated 30 fps clock, 300 frames, index pattern)
decodes with 300 frames, strictly increasing ticks equal to 20 × k, duration 10.0 s, indices 0...299
in order, one video track, no audio track, no metadata (REC-003-S1); the stalled writer keeps ≤ 3 in
flight and counts the rest as dropped (S2); timeline rules (S3).

## B. Simulator (iOS 27.2), once

```bash
xcodebuild test -scheme Compositor -destination 'platform=iOS Simulator,id=<udid>' \
  -only-testing:CompositorTests/CompositorRecordingTests -only-testing:FrameRecordingTests
```

The simulator may not encode HEVC; the writer falls back to H.264 and the test records which codec
ran.

## C. App (simulator)

`-only-testing:projectM-iOSTests/VideoRecordingAppTests` (refusals, every stop reason, a Photo host
recording offscreen frames) and `-only-testing:projectM-iOSUITests/VideoRecordingUITests` (Photo
visual, `-uitestRecordingDirectory`: Record → indicator → ~2 s → Stop → probe
`video <codec> <w>x<h> frames=<n> duration=<s> audio=0` with n ≥ 2).

## D. Devices (owner, last)

1. D1 and D3 (iPadOS 26.5): record 60 s of the Camera and the Circular Spectrum at the device's
   size; read the probe or the file in Files: frame rate, dropped frames, thermal state before and
   after (Settings is not needed: the FR-048 overlay shows it).
2. D3 with a 4K external display: record 60 s of the Photo visual on the display.
3. Save to Files and iCloud Drive; play the files in Files.
