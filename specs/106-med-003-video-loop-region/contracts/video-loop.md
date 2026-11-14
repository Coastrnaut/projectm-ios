# Contract: Video loop region (MED-003)

## Reader seam (`VideoFrameReading`, additive)

- `open(startNanoseconds:endNanoseconds:)`: as `open(startNanoseconds:)`, reading stops at the end
  (nil after it). Default: calls the one-argument `open` (pictures past the end are discarded by
  the session).
- `prepare(startNanoseconds:endNanoseconds:)`: a hint that the next `open` will use these
  arguments. Default: nothing. Must never throw; a failed preparation just means a normal open.

## Pipeline

- `start(atNanoseconds: Int64, region: VideoLoopRegion?, mediaStartNanoseconds: Int64?)`.
  `start(atNanoseconds:)` = `region: nil, mediaStartNanoseconds: nil` (MED-002 behaviour).
- Every `open` of a session starts at a time inside the effective region (tests record them).
- Every queued `TimedFrame.mediaNanoseconds` lies in [in, out), except the single fallback picture
  covering in for a pass that has no picture inside.
- Playback times only increase across passes; the wrap from the last picture before out to the
  first picture at in adds exactly the region's remainder (no extra time).

## Layer (`VideoLayerSource`)

- `loopRegion: VideoLoopRegion?` (nil: whole file). Setting it while playing restarts decoding at
  the shown picture if inside, else at in; the clock is kept; a held picture outside is dropped.
- Read-outs: `shownMediaNanoseconds`, `mediaDurationNanoseconds`, `wraps`,
  `maxWrapLatenessNanoseconds`.

## Scene (`SceneAsset.videoLoop`)

`"loop": {"inMilliseconds": 1500, "outMilliseconds": 3000}` on a `video` asset. Absent = whole
file. Malformed = whole file. Kept verbatim by apps without MED-003.

## DEBUG probes (`-uitestDiagnostics`)

- `videoMediaFrameIndex`: ⌊shown file time × 30⌋ (the 30 fps fixture), or "none".
- `videoLoopRegion`: "<in ms>-<out ms>" of the applied region, or "whole".
- `videoLoopStats`: "wraps=<n> gap=<frames> early=<n> recovered=<n>".
