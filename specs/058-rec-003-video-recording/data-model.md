# Data Model: REC-003 Video Recording

All values are in memory; the only stored item is the temporary video file (deleted after export).

## RecordingSettings (package, plain Swift)

| Field | Type | Default | Rule |
|---|---|---|---|
| `maxFrameRate` | Int | 30 | 1...60; interval = 600 / rate ticks (REC-003-R6) |
| `maxLongSide` | Int | 1920 | ≥ 16, even |
| `maxDurationSeconds` | Int | 600 | > 0 (R11) |
| `framesInFlight` | Int | 3 | ≥ 1 (R7) |
| `codecPreference` | [RecordingCodec] | [.hevc, .h264] | tried in order (D2) |
| `timescale` (static) | Int32 | 600 | ticks per second (R5) |

`RecordingCodec`: `hevc`, `h264` (title, four-character code).

## RecordingGeometry

Built from the drawable's pixel size: `sourceWidth/Height` = drawable rounded down to even;
`outputWidth/Height` = source scaled to fit `maxLongSide`, rounded to even, at least 2. nil when the
drawable is smaller than 2 × 2.

## RecordingTimeline

State: `originNanoseconds` (first admitted frame), `lastWrittenTick`, settings. `admit(ns)` →
`Admission`: `.candidate(tick)`, `.skippedRate`, `.droppedNotIncreasing`, `.durationReached`.
`markWritten(tick)` after the gate admits. `endTick` = last + interval. Invariant: written ticks are
strictly increasing and start at 0.

## RecordingFrameGate

`capacity` (= framesInFlight), `inFlight`, `maxInFlight` (observed), behind a `Mutex`.
`tryAcquire() -> Bool`, `release()`.

## RecordingStatistics

`written`, `droppedBusy` (gate full or no pixel buffer), `droppedNotReady` (encoder not ready),
`droppedNotIncreasing`, `skippedRate`. `dropped` = sum of the three drop counts.

## RecordingStopReason

`user`, `durationReached`, `background`, `paused`, `blackedOut`, `visualChanged`, `sizeChanged`,
`presentationLost`, `writerFailed` — each with its notice (nil for `user`).

## RecordingRefusal

`noVisual`, `notRecordable` (projectM), `outputBlackedOut`, `paused`, `busy` (recording or
finishing) — each with its notice.

## RecordingFailure

`encoderUnavailable` (no codec could start), `pixelBufferUnavailable`, `writerFailed(String)`,
`tooFewFrames`, `cancelled`.

## RecordedVideo

`url`, `codec`, `width`, `height` (output), `frameCount` (= written), `durationSeconds`
(= endTick / 600), `statistics`.

## RecordedVideoInfo (inspector read-back)

`codec` (four-character code), `width`, `height`, `frameCount`, `presentationTicks` ([Int64] at
1/600 s), `durationSeconds`, `videoTrackCount`, `audioTrackCount`, `metadataCount`; `summary` for the
DEBUG probe: `"video hevc 1178x2556 frames=58 duration=1.93 audio=0"`.

## Coordinator state (app)

`idle` → (Record, no refusal) → `recording(startedAt media tick 0)` → (stop event) → `finishing` →
`idle` with either the mover shown (file) or a notice (failure / too few frames).
