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

## Verified on the build Mac, 2026-11-12 (Mac Studio, Xcode 27.2; feature worktree)

| Suite | Where | Result |
|---|---|---|
| `AudioCore` | macOS host | 84 tests, 0 failures (79 with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`) |
| `CaptureKit` | macOS host | 236 tests, 0 failures |
| `CaptureUI` | macOS host | 30 tests, 0 failures |
| `Diagnostics` | macOS host | 10 tests, 0 failures |
| `AudioCore`, `CaptureKit`, `CaptureUI` | iOS 27.2 simulator (iPhone Air) | 84, 236 and 30 tests, 0 failures |
| App unit tests | iOS 27.2 simulator | 69 tests; the only failure is `PresetTests.testBundledIncludedScopeMatchesRelease1_0`, which needs the full preset library the worktree does not have |
| `TransportUITests` (3), `ImportedAudioUITests` (5), `StatusUITests` (7), `VisualizerUITests` (7) | iOS 27.2 simulator, real time | 22 tests, 0 failures |
| `scripts/test_scripts.py`, `check_compliance.py`, `validate_docs.py` | macOS host | 96 tests OK (1 skipped); OK; OK |

Not run or not conclusive in the worktree:

- `Rendering` and `ANGLERendering` do not build for the macOS host (iOS-only engine framework). On
  the simulator, 3 of 28 and 11 of 43 tests fail with "Could not parse preset file": the worktree
  has no `Vendor/projectM` submodule, so the upstream test preset is missing. No other failure.
  They have to be run on the integration checkout.
- The Linux package tests (no Linux host here).
- Everything on a physical device (section E).

What the simulator UI test adds to the offline tests: the cut runs against a real-time engine
(pause, play, a drag and a touch on the scrubber, next track into another sample rate and channel
count, stop playback) and the status reads "Paused" and returns to "Active audio".

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
