# Contract: REC-006 record frame rate

## C1 Frame grid (RecordingTimeline)

- Interval I = 600 / fps ticks (24 → 25, 30 → 20, 60 → 10). Written ticks are m × I, strictly increasing.
- Slot of a frame at t ns after the origin: m = (t × fps + 500_000_000) / 1_000_000_000 (integer division).
- Per offered frame, in order:
  1. t before the origin, or t ≤ the last written frame's time → `droppedNotIncreasing`.
  2. m × I ≥ the duration limit → `durationReached`.
  3. m < next free slot → `skippedRate`.
  4. d = min(t − previous offered frame time, one slot) when a previous frame exists. If t is before the slot time, |t + d − slot| + 1 µs < |t − slot| (closer than 1 µs is a tie: clock rounding) and t + 1.5 d is before the window's end → `skippedRate` (a nearer frame is expected).
  5. Otherwise `candidate(tick: m × I)`; `markWritten(tick:)` makes slot m + 1 the next free slot.
- Constant time, no allocation; one thread (the frame loop).

## C2 Dropped frames

- On each append at tick T after a previous append at tick L: `droppedSlots += (T − L) / I − 1`.
- `RecordedVideo.droppedFrames = droppedSlots`; `frameCount + droppedFrames = (last tick / I) + 1`.

## C3 Rate availability (`RecordingFrameRateCatalog.availability(rate:codec:width:height:capabilities:)`)

- display: rate > `maxFramesPerSecond` → `displayLimit`.
- render cap: `renderLimit` with rate > its maximum → `renderLimit`.
- encoder: codec and size given and rate > `maxEncodedFramesPerSecond(codec, width, height)` → `encoderLimit`.

## C4 Resolution at Record (`RecordingFrameRateCatalog.resolve(profile:choice:drawableWidth:drawableHeight:capabilities:)`)

1. Explicit rate r: if unavailable (display, render cap), r' = the highest supported rate below r that is available; rate notice.
2. REC-005 `RecordingQualityCatalog.resolve(profile, frameRate: r' or nil)`; refuse → refuse.
3. Plan rate above the render cap or the encoder limit for the plan's codec and output size → the highest supported rate within both; rate notice.
4. Notice: profile fallback notice, then the rate notice ("Recording at 30 fps: Low Power Mode limits the visual to 30 fps."), joined by a space.

## C5 Settings UI

- Section "Recording frame rate" under "Recording quality". Rows (buttons): `recordingFrameRate.profile` ("Profile default (30 fps)"), `recordingFrameRate.24`, `.30`, `.60`. Disabled rows show their reason; the selected row has a checkmark and the selected trait; the VoiceOver label is "24 fps" or "60 fps, unavailable: <reason>".
- Profile rows (REC-005) describe the effective rate.
