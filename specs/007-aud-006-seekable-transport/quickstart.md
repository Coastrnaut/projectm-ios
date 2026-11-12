# Quickstart: validating AUD-006 Seekable transport

Run from the repository root. Simulator and Mac results are not device evidence.

## A. Packages on the Mac

```bash
swift test --package-path Packages/AudioCore
swift test --package-path Packages/CaptureKit
swift test --package-path Packages/CaptureUI
swift test --package-path Packages/Diagnostics
```

Expected: all pass. The acceptance tests are `SeekableGraphTests` and `TransportPipelineTests`
(a generated track whose samples state their frame index; after a seek every delivered frame is
the target frame or later, in order, and the position is exact).

## B. Packages on the iOS 27.2 simulator

```bash
cd Packages/CaptureKit && xcodebuild test -scheme CaptureKit -destination 'id=<udid>' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO \
  > ../../.build/scratch/capturekit-sim.log 2>&1
```

Same for `AudioCore` and `CaptureUI`. Grep the log for `: error: `, `Executed`, `** TEST`.

## C. The app on the simulator

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'id=<udid>' \
  -derivedDataPath .build/dd -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO -only-testing:projectM-iOSUITests/TransportUITests \
  > .build/scratch/app-transport.log 2>&1
```

Expected: the transport appears for an imported track and for the reference track, not for
Microphone; Pause shows "In-App Playback · Paused" and holds the time; the scrubber moves the
time; Next and Previous change the title; Stop playback returns to 0:00.

## D. By hand (simulator or device)

1. Import two tracks, play the upper one. The controls show its title, the transport buttons, the
   scrubber and both times.
2. Drag the scrubber: the times follow the finger; on release the sound and the picture continue
   from there.
3. Pause playback: silence, "Paused", time holds. Home, return: still paused. Play: continues.
4. Stop playback: 0:00, visualizer still on screen. Play: from the start.
5. Next track at the last track wraps to the first. Previous track after more than 3 s restarts.
6. Let a short track end: the next starts. With one track: it repeats without a gap.
7. VoiceOver: every control is named; swipe up and down on "Playback position" moves 10 s.

## E. Device phase (`{device}`, later)

Routes (headphones, Bluetooth), interruptions (call, alarm) during pause and during play, lock and
unlock, and listening for stale audio after a seek on hardware. See tasks.md.
