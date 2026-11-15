# Research: FX-010 Echo Feedback

## FX-010-D1: Own pass in the output-effect walk

- **Decision**: `EchoPass` with two fragment functions, `cmp_echo` (output) and `cmp_echo_capture` (store), run in
  the `encodeOutputEffects` walk at Echo's place in `outputEffectOrder`; both spliced at the existing compile site and
  added to `CompositorShaderSources.archived`.
- **Rationale**: FX-006/FX-007's proven pattern (own function, pooled pictures released when unused, PERF-004
  allocation counting); the echo needs past frames, so it cannot live in the per-pixel output pass.
- **Alternatives**: extending `TrailsPass` (Trails keeps one recursive picture; echoes need discrete copies and
  their own reset and memory rules); MPS (new framework dependency).

## FX-010-D2: Bounded history: a ring of the cap, at a bounded history size

- **Decision**: exactly 4 history pictures (the cap, whatever the count), `rgba16Float`, at the history size: each
  axis ceil(output ÷ 2), rounded to the nearest multiple of 16 (at least 16); when the longer side exceeds 960 both
  sides are scaled by 960 ÷ longer and rounded down to a multiple of 16 (at least 16). Worst case
  4 × 960 × 960 × 8 = 29,491,200 bytes. Per device class (history size, bytes): D1 iPhone 15 2556 × 1179 → 960 × 432,
  13,271,040; D2 iPad Pro M5 2752 × 2064 → 960 × 720, 22,118,400; D3 iPad A16 2360 × 1640 → 960 × 656, 20,152,320;
  a 4K external display 3840 × 2160 → 960 × 544, 16,711,680; 1080p → 960 × 544, 16,711,680.
- **Size class**: the history size itself. A resize that leaves it unchanged keeps the ring and its contents; one that
  changes it returns the 4 pictures and takes 4 new ones (and empties the history).
- **Rationale**: a frame-exact delay line would need count × delay frames (at 500 ms and 4 echoes, 120 frames at
  60 fps: gigabytes at full size). Storing one frame per delay interval keeps the ring at 4 whatever the delay. Faded
  copies at half resolution look the same as full-size copies; the live picture stays full size.
- **Alternatives**: full-resolution ring (13-66 MB per picture on the test devices); rgba8 history (loses the linear
  HDR range of the composite); count-sized ring (memory then changes with the setting, against "allocate once").

## FX-010-D3: Storing schedule on the frame clock (sample and hold)

- **Decision**: `EchoSchedule` (plain Swift): after a reset the next frame stores at once; otherwise the time since
  the last store accumulates the frame clock's durations and a frame stores when it reaches the delay (1 µs
  tolerance), subtracting the delay; at most one store per frame (any excess beyond one delay is dropped). The store
  is encoded after the frame's echo pass, into the oldest slot, so echo k reads the k-th most recent store, between
  (k − 1) × delay and k × delay old plus at most one frame. Delay 10…500 ms, default 100 ms.
- **Rationale**: frame-rate independent like Trails' decay; deterministic with injected frame durations (tests use
  exact binary durations such as 62.5 ms).
- **Alternatives**: delay in frames (echo spacing changes with the frame rate); storing every frame and picking frames
  (needs the delay line of D2).

## FX-010-D4: Combination and weights

- **Decision**: raw weight of echo k is decay^k (k = 1…N, decay 0.1…0.9, default 0.6); if their sum exceeds the
  weight cap (1, or less under ACC-012) all are scaled by cap ÷ sum. Only stored (valid) frames count: with V valid
  stores, n = min(N, V) echoes are drawn, weights computed for those n. Output = max(current, Σ w_k × stored_k) per
  channel, premultiplied alpha included; a non-finite current pixel is returned unchanged. With n = 0 no echo pass runs
  (the input itself is shown, bit for bit).
- **Rationale**: Σ w ≤ 1 makes the echo term at most the brightest stored value, and the max never exceeds the
  brightest of current and stored frames: no new peak brightness, the live picture never dims. Same blend family as
  Trails (ADR-0051).
- **Alternatives**: additive (up to 2× brightness, a flash risk); normalised mix (dims the live picture).

## FX-010-D5: Capture (downsample)

- **Decision**: each history pixel averages 4 bilinear samples of the input at ±0.25 history pixels around its centre
  (normalised coordinates, clamp to edge); each sample is sanitised per channel (non-finite → 0, negatives → 0, alpha
  ≤ 1) before averaging. At an exact 2× ratio the 4 samples land on the 4 covered pixel centres (an exact 2 × 2 box);
  at larger ratios they cover 4 × 4 pixels with less aliasing than one sample.
- **Rationale**: cheap (4 samples per history pixel), exact at 2×, and the history never holds non-finite values.

## FX-010-D6: Output sampling and the CPU reference

- **Decision**: echo k is sampled bilinearly at the output pixel's normalised centre (p + 0.5) ÷ size. The CPU
  reference (`EchoFeedback.downsample`, `EchoFeedback.referencePixel`/`reference`) mirrors both passes with the same
  coordinate mapping and clamp; GPU vs CPU within 2/1024 per channel at 2× ratios (sub-texel fractions 0, 0.25, 0.75).

## FX-010-D7: Resets and render caching

- **Decision**: the schedule empties (no valid stores; next frame stores at once) on: turning Echo on, a history-size
  change, `resetFeedback()`, `resetFlashHistory()`, `resetRenderHealth()`, an output-format change, a transition start
  and an unfinished frame — the triggers Trails uses (FX-009-R5). A count, delay or fade change keeps the history.
  CMP-013's composite reuse stays allowed: the echo pass runs every frame on the (reused) composite, so reuse changes
  nothing.

## FX-010-D8: Chain position and storage

- **Decision**: `OutputEffectKind.echo = "fx.echo"`, appended after the last existing kind (FX-008's radial blur may
  land in parallel; whichever merges second appends after the other, never reorders). Scene entry parameters
  `count` (0…4, rounded; > 4 → 4 reported as clamped), `delay` (seconds 0.01…0.5), `decay` (0.1…0.9).

## FX-010-D9: ACC-012

- **Decision**: `EchoFeedback.limited(by:)`: a profile that caps intensity multiplies the weight cap by its intensity
  limit; Reduce flashing caps it at 0.5; a cap of 0 turns Echo off. The app applies the effective value, re-applied in
  `applyReduceFlashing` like Trails. The FX-019 flash guard measures the shown frame (after Echo) as always.
