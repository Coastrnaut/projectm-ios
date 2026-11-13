# Research: MED-002 Import Video Layer

Decisions are numbered `MED-002-D1…` and cited from code comments.

## MED-002-D1 Decoder: `AVAssetReader`, not `AVPlayerItemVideoOutput`

- **Decision**: An `AVAssetReader` with an `AVAssetReaderTrackOutput` (32BGRA,
  `alwaysCopiesSampleData = false`) on a dedicated decode thread, pulled one sample at a time.
- **Rationale**: Determinism and bounded memory. The reader is pull-based: nothing is decoded until
  the thread asks, so a counting semaphore of 3 is a hard bound; every picture comes with its exact
  presentation timestamp, so "the frame for time t" is computed against an injected clock in tests.
  `AVPlayerItemVideoOutput` is paced by an `AVPlayer` clock (wall time, not injectable), buffers on
  its own terms, and brings a player whose audio session behaviour would have to be neutralised.
- **Alternatives**: `AVPlayerItemVideoOutput` (above); `VTDecompressionSession` on raw samples
  (more code, same result; a candidate for MED-014's hardened decoder behind the same seam).

## MED-002-D2 Pixel format and color

- **Decision**: Ask the reader for 32BGRA; wrap each `CVPixelBuffer` with `CVMetalTextureCache` as
  `.bgra8Unorm_srgb`, so the sampler returns linear light; alpha 1 (opaque), so the premultiplied
  picture equals the color.
- **Rationale**: The system converts video range Y′CbCr (BT.601/709 matrices as tagged) to full-range
  R′G′B′; treating BT.709's transfer as sRGB is the same approximation the camera layer (CAM-001)
  uses, and needs no shader matrix code. A 4:2:0 two-plane path would halve memory but add a
  per-matrix shader; deferred (MED-014 may revisit for 4K memory).
- **Color test tolerance**: the fixture's solid colors pass through an H.264 encoder (lossy, 4:2:0,
  video range), so the decoded 8-bit code may differ from the written one by a few codes. S3 is
  checked as "the layer's linear output is within 1/255 of the linear value of the code the
  decoder produced" (the layer's own conversion), plus "within 6 codes of the written color" for the
  codec (stated, not part of the 1/255 rule).

## MED-002-D3 Bounded queue and dropping

- **Decision**: `VideoDecodePipeline<Frame>` (plain Swift): a ring of at most `capacity` (3) frames
  under an `NSLock`; a `DispatchSemaphore(value: capacity)` counts free slots. The decode thread
  waits on the semaphore before reading each picture (so it never holds more than `capacity`
  undelivered pictures), and the render side signals once per picture it removes. `render` uses
  `NSLock.try()`: if the decoder holds the lock this instant, the held picture is drawn again (no
  wait). Selection: remove every queued frame with `pts ≤ t`; the newest becomes the shown frame,
  the others count as dropped (late). A counter records the deepest the queue has been.
- **Rationale**: The bound holds by construction (a semaphore permit per queued picture) and is
  observable (`maxDepth`), which is the row's acceptance.

## MED-002-D4 Playback clock

- **Decision**: `VideoPlaybackClock` (plain Swift, integer nanoseconds) advances by the difference of
  successive presentation times; the first frame starts at 0; a difference > 1 s (pause, background,
  long stall) advances 0; a time earlier than the previous counts as 0. Reset on new content.
- **Rationale**: The display link's `targetTimestamp` is the presentation time the compositor
  already passes (CMP-001-R3). Using real differences (not `frameDuration`, which CMP-001 clamps
  to 0.1 s) keeps the intended rate through hitches; ignoring long gaps continues after a pause
  without a separate pause API. A genuine hang > 1 s freezes the video by that much (accepted).

## MED-002-D5 Looping and seeking

- **Decision**: The decoder emits timestamps on an unwrapped timeline: `loop × duration + pts`.
  At end of file it reopens the reader at 0 and increments `loop` (MED-002-R11). If, before reading,
  the playback target is more than 1 s past the next expected timestamp, it reopens the reader at
  `target mod duration` with the matching loop (a seek), flushing nothing (the queue only holds
  frames ≤ 3 ahead). An empty file or a reader that produces no picture in a loop is a `.damaged`
  failure (no busy loop).
- **Rationale**: Monotonic timestamps make selection simple and keep MED-003 (regions: reopen at
  `in` instead of 0) and MED-004 (speed: clock rate) local changes.

## MED-002-D6 Import: remux without metadata or soundtrack

- **Decision**: `VideoSanitizer`: build an `AVMutableComposition` with one video track inserted over
  the source track's time range, copy the source track's `preferredTransform`, and export it with
  `AVAssetExportPresetPassthrough` to `.mov` with `metadata = []` and a `metadataItemFilter` of
  `.forSharing()`. No sample is re-encoded. The probe reads only the track's format descriptions
  (codec), natural size, preferred transform, nominal frame rate and time range.
- **Rationale**: Clarification 1. A composition carries no asset- or track-level metadata of the
  source; passthrough keeps quality and costs only I/O.
- **Alternatives**: keep the original (location kept); `AVAssetWriter` passthrough of samples (more
  code for the same output).

## MED-002-D7 Limits and codecs

- **Decision**: 500 MB file, ≤ 4096 px longest side (after rotation it is the same number), nominal
  frame rate ≤ 60.5 (59.94 passes), codec FourCC `avc1`/`avc3` (H.264) or `hvc1`/`hev1` (HEVC),
  duration > 0. Then the first picture must decode (an `AVAssetReader` read of one sample), else
  `.damaged`. File size from `URLResourceValues.fileSize` (not a required-reason API).

## MED-002-D8 Background, pause and teardown

- **Decision**: The layer exposes `suspendDecoding()` (cancel the session: release reader, queue and
  texture cache entries) and restarts decoding lazily at the clock's position on the next render.
  The host calls it on background and scene disconnect; while merely paused the decoder fills the
  queue and sleeps on the semaphore (no CPU). Changing `content` cancels the session.
- **Cancellation**: the session's `cancelled` flag is set and its semaphore signalled once; the
  thread exits at its next check. Sessions are separate objects, so a stale thread can never touch
  a new queue.

## MED-002-D9 App structure

- **Decision**: Mirror MED-001: `VideoStore` (Application Support/Videos, `settings.video.id`,
  `<UUID>.mov` only), `VideoCoordinator` (pickers, notice, remove), `VideoVisualHost` (video under
  circular spectrum), Settings "Video" section, Debug `-uitestSeedVideo` (generates the fixture with
  `AVAssetWriter` and imports it through `VideoStore`). The Photos picker item arrives as a file
  through a `Transferable` `FileRepresentation(importedContentType: .movie)`.
- **Diagnostics**: with `-uitestDiagnostics`, static texts `videoFramesShown` and `videoFrameIndex`
  (the shown picture's index on the fixture timeline, `pts × fps`, read by the existing diagnostics
  refresh, not per frame).

## MED-002-D10 Linux shape

- **Decision**: limits, errors, track info, clock, queue/pipeline and the reading protocol use only
  Foundation and Dispatch (`NSLock`, `DispatchSemaphore`, `Thread`), so they build and test on
  Linux with a fake reader. AVFoundation files sit behind `#if canImport(AVFoundation)`; the layer
  and the texture-producing reader also behind `canImport(Metal) && !COMPOSITOR_NO_METAL`.
