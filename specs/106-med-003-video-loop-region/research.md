# Research: MED-003 Video Loop Region

All decisions by Claude under owner rules 4 and 9 (2026-11-14).

## MED-003-D1: Region units and clamping

- **Decision**: In and out are integer nanoseconds inside the player (the pipeline's unit) and
  integer milliseconds where they are stored (settings, scenes). `effective(duration:)`: no region
  → [0, duration); negative values → 0; out beyond duration → duration; out < in + 0.25 s → out =
  in + 0.25 s, and if that passes the end, in = duration − 0.25 s; a video shorter than 0.25 s
  plays whole.
- **Rationale**: integers keep comparisons exact (no floating rounding at the joint); milliseconds
  are fine-grained enough for a 0.1 s slider and keep scene JSON small and readable.
- **Alternatives**: `CMTime` in the model (not plain Swift on Linux); seconds as `Double` (rounding
  at frame boundaries); snapping to frames (needs the frame rate in the store; unnecessary because
  the pass rules below never show a picture outside).

## MED-003-D2: Timeline mapping

- **Decision**: a session keeps `base` (the playback time at which in of pass 0 is shown) and
  `L = out − in`. A picture of pass k with file time pts has playback time
  `base + k × L + (pts − in)`. A start at playback p with a media hint m inside the region uses
  `base = p − (m − in)`; without a hint (whole-file start, as MED-002) `m = in + (p − in) mod L`
  with `base` the matching multiple. Catch-up seeks compute k and the offset from `base`. The
  timeline still only increases, so `take(upTo:)`, the clock and the queue are unchanged.
- **Rationale**: the smallest change to MED-002's proven unwrapped timeline (base 0, in 0, L =
  duration reproduces it exactly).
- **Pictures outside the region**: pictures before in are skipped; the latest skipped one is kept
  and queued only if the pass would otherwise end with no picture (a region shorter than a slow
  clip's frame interval). A picture at or after out ends the pass and is not queued.

## MED-003-D3: Seamless joint (pre-roll)

- **Decision**: (1) the reader's time range ends at out, so the decoder never reads past it; (2)
  when the picture just read is within 0.5 s of out the session calls
  `prepare(startNanoseconds: in, endNanoseconds: out)` once per pass; `AVVideoFrameReader` then
  creates and starts a second `AVAssetReader` at in, which AVFoundation begins decoding in the
  background, and swaps it in when the next `open` asks for that start and end; (3) the 3-picture
  queue keeps feeding the display while the swap happens.
- **Rationale**: opening a reader costs a keyframe decode; doing it ahead hides it. Preparing only
  near the end keeps a second reader (and its decoded buffers) alive for at most 0.5 s per pass.
- **Alternatives**: one reader with several time ranges (`AVAssetReader` cannot restart; ranges are
  for one pass only); `AVPlayerLooper` (an `AVPlayer` stack, not the compositor's texture path);
  caching decoded pictures of the region (memory scales with region length × 4K).

## MED-003-D4: Recovery rules

- **Decision**: per pass: a clean end (picture at out, or EOF) resets a bad-pass counter; EOF before
  out when out is before the file's end counts `earlyEnds`; a reader error after the pass queued a
  picture counts `recoveredErrors` and starts the next pass at in; a pass that queued no picture
  (an error or an end) is a bad pass; three bad passes in a row, or any failed open, end the
  session as `.failed` (MED-002's fallback and notice). A pass ending in an error is also bad when
  it repeats: three error-ended passes in a row fail.
- **Rationale**: an error near the end of an otherwise good file keeps playing; a file that fails
  every pass at the same place does not loop a fragment forever; a damaged copy still fails at the
  container check (MED-014).
- **MED-002 test impact**: `testReaderErrorsEndTheSessionWithTheirType` (a reader failing at
  picture 5 every pass) now fails after three passes instead of one; the test drains the queue
  until the state is `.failed`.

## MED-003-D5: Measuring the gap

- **Decision**: the layer records, whenever the shown picture's file time goes backwards (a wrap),
  the playback time minus the new picture's presentation time ("wrap lateness") and keeps the
  maximum. Gap in frames = lateness ÷ the video's frame interval, rounded down. With the fake
  reader and a decoder that keeps up the gap is 0 by test. On the simulator it is read through the
  DEBUG probe and reported, not asserted (no wall-clock assertions); D1 is the device check.

## MED-003-D6: Scene field

- **Decision**: `loop: {"inMilliseconds": Int, "outMilliseconds": Int}` on the `video` asset, read
  and written by `SceneAsset.videoLoop` over `extra`. Written only for a non-whole region.
- **Rationale**: assets already carry unknown fields verbatim (SCN-001), so older apps keep the
  field and re-save it; no decoder change means no `droppedField` warning and no version bump —
  the CMP-006 rule ("an optional field, no version change") with even less risk. QA-004's matrix
  is unaffected: no old document changes meaning (absence = whole file).
- **Alternatives**: a layer field (the layer's content object is closed: unknown keys there are
  dropped by older apps); a new asset type (breaks older apps' media resolution).

## MED-003-D7: Settings key

- **Decision**: `settings.video.loop` holds `{"id": <UUID string>, "inMilliseconds": Int,
  "outMilliseconds": Int}`. Read only when `id` is the stored video's; otherwise ignored and
  removed. Remove Video and `makeCurrent` of another ID remove it. It is listed in
  `AppSettings.allKeys` (so `-uitestResetNotice` clears it) and in `ALLOWED_KEYS`.
- **Rationale**: the app stores one video; keying by ID guarantees a new video never inherits an
  old region.
