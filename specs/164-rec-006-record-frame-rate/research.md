# Research: REC-006 Record frame rate

## REC-006-D1: Exact frame grid instead of rounded real times

- **Decision**: Slot n is at n × (600 / fps) ticks of the 1/600 s timescale from the first written frame (25, 20, 10 ticks for 24, 30, 60 fps). A frame at time t (ns from the first frame) belongs to slot m = ⌊(t × fps + 0.5 × 10⁹) / 10⁹⌋ (integer arithmetic, the slot whose half-open window [n − ½, n + ½) intervals holds t).
- **Rationale**: Editors expect constant-rate files; exact times make the nominal frame rate exact and remove the ±¼-interval wobble of REC-003. Integer arithmetic keeps 24 fps (41.666… ms) exact.
- **Alternatives**: keep real times with a rate cap (REC-003; times are not n/fps, and the cap after a stall drifts the grid); timescale 1/fps per file (breaks REC-004 audio placement and the shared 1/600 s read-back).
- **Amends**: ADR-0027 decision 2 (new ADR).

## REC-006-D2: Nearest frame per slot with a one-frame prediction

- **Decision**: A frame in slot m (m ≥ the next free slot) is written unless it lies before the slot time and the next frame, predicted at t + d (d = the last offered frame interval, at most one slot interval), would be strictly nearer to the slot and would still land well inside the window (t + 1.5 d before the window's end). Ties go to the earlier frame. A frame in an already written slot is skipped (`skippedRate`, not a drop).
- **Rationale**: Writing must be decided on the frame loop without waiting and without copying every frame on the GPU. With steady input this picks exactly the nearest frame (60 → 24 alternates 2 and 3 frames per slot, choosing 33.3 ms over 50 ms at ties); the 1.5 d margin keeps jitter from deferring to a frame that falls out of the window.
- **Alternatives**: the first frame in the window (picks frames up to half a slot early: 120 → 30 takes the 25 ms frame instead of 33.3 ms); buffer one frame per slot on the GPU and choose afterwards (an extra copy per rendered frame, against REC-006-R11).

## REC-006-D3: Empty slots are skipped and counted, not repeated

- **Decision**: No sample is written for a slot without a frame; the writer queue adds (tick − last tick) / interval − 1 to `droppedSlots` on each append. A player holds the previous picture through the gap, which is what a repeat would show.
- **Rationale**: Repeating needs a retained pixel buffer and a burst of appends right after a stall, when a real-time encoder is least able to take them; counting at the writer covers every cause (stall, slow loop, queue full, encoder not ready) in one place.
- **Consequence**: Without drops the file is constant-rate (`nominalFrameRate` = fps); with drops `minFrameDuration` is still 1/fps and the track's nominal rate is frames / duration.

## REC-006-D4: Which rates are available

- **Decision**: Rate r is available when r ≤ the display's `maximumFramesPerSecond`, r ≤ the render cap (QualityGovernor: 30 fps in Low Power Mode or at serious/critical thermal state), and r ≤ the encoder's frame-rate limit for the planned codec and size. Order of reasons: display, render cap, encoder. Reasons: "This display shows at most N fps.", "Low Power Mode limits the visual to 30 fps.", "The device is too warm; the visual is limited to 30 fps.", "This device encodes at most N fps at W×H."
- **Rationale**: Recording above the render rate only produces dropped slots. VideoToolbox publishes no per-size rate limit through public API, so the real source reports 60 (the highest rate offered); the protocol requirement lets tests inject limits and a future source refine it.
- **Capability seam**: `RecordingEncoderCapabilities` gains `renderLimit` and `maxEncodedFramesPerSecond(_:width:height:)` with default implementations (nil, 60) so REC-005's sources and stubs compile unchanged.

## REC-006-D5: Resolution at Record and notices

- **Decision**: (1) Explicit rate: if unavailable for display or render cap, use the highest available supported rate below it. (2) REC-005 profile resolution with that rate as the override (Profile default: the profile's rate, REC-005 unchanged). (3) If the plan's rate exceeds the render cap (Profile default) or the encoder limit for its codec and size, lower it to the highest supported rate within both. Each lowering produces "Recording at N fps: <reason>."; with a profile fallback too, the notice is the profile notice, a space, then the rate notice. Both start with "Recording at ", so StatusEvents classifies them as X9c with no change.
- **Rationale**: Keeps REC-005's profile semantics for Profile default and puts the rate decision where the user made it.

## REC-006-D6: Nominal frame rate in the file

- **Decision**: `AVVideoExpectedSourceFrameRateKey` = the effective rate (already written from `maxFrameRate`), the exact grid, and `mediaTimeScale` 600. The read-back reports `AVAssetTrack.nominalFrameRate` and `minFrameDuration` (in ticks).
- **Rationale**: MP4 has no separate frame-rate field; AVFoundation derives the nominal rate from the samples, so an exact grid is what makes it equal the selection.

## REC-006-D7: Audio

- **Decision**: Unchanged. REC-004 places audio by host time from the first frame; slot times differ from render times by at most half a slot (≤ 20.8 ms at 24 fps) and never drift because slots are anchored to the first frame's clock.

## REC-006-D8: Fixture design (owner rule 7)

- **Decision**: 64 × 48 drawable, offline writer, 1 s per case, cleared frames with a per-frame grey level; patterns: 60 Hz, 120 Hz, 120 Hz ± 2 ms and 60 Hz ± 3 ms (seeded), 60 Hz with one 200 ms stall at 0.4 s. Rates 24, 30, 60. Expected drops for the stall come from an independent window count (slots whose window holds no frame) and must match exactly; jitter at most 1% of slots. Representative cases, not a cross-product: steady 60/120 at all three rates, stall at all three rates, jitter at 24 and 60.
