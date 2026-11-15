# Research: FX-007 Directional Blur

## FX-007-D1: Own pass in the output-effect walk

- **Decision**: A separate full-screen pass `cmp_directional_blur` (`DirectionalBlurPass`) writing one pooled
  picture, run in FX-006's `encodeOutputEffects` walk at its place in `outputEffectOrder`.
- **Rationale**: the blur reads neighbouring pixels, so it cannot live in the per-pixel output pass; FX-006's pass is
  the proven pattern (own function, own picture, pooled, released when unused, PERF-004 allocation counting).
- **Alternatives**: FX-001's `BloomEffect` blur (VisualEffects, native spectra only, separable 2-D); Metal
  Performance Shaders (a new framework dependency and no directional kernel).

## FX-007-D2: Fixed tap budget and kernel

- **Decision**: K = 16 taps (`DirectionalBlur.tapCount`, shader constant `cmp_dirblur_taps = 16`). Tap i (0…15) sits
  at u_i = (2i − 15) ÷ 15 ∈ [−1, 1] along the axis, offset u_i × radiusPx × d, with d = (cos θ, −sin θ) in texture
  coordinates (y down; components with |c| < 1e-6 snapped to 0, so 0° and 90° are exact). Weights
  w_i = exp(−u_i² ÷ (2 × 0.5²)) normalised to sum 1 (σ = radius ÷ 2): independent of the radius, so they are computed
  once in Swift and passed in the 80-byte fragment block with the step vector.
- **Rationale**: the cost is fixed (16 samples) at every radius; Gaussian weights avoid the hard ends of a box; at
  the maximum radius (2% of 1179 px ≈ 24 px) the spacing is ≈ 3 px, smooth with linear filtering.
- **Alternatives**: a radius-dependent tap count (cost grows, against the row); 17 taps with a centre tap (16 is the
  brief's budget; the pixel is reached through the two innermost taps); box weights (visible banding at the ends).

## FX-007-D3: Sampling and edges

- **Decision**: hardware linear filtering (`sampler(coord::pixel, filter::linear, address::clamp_to_edge)`), sample
  positions clamped to the pixel-centre rectangle [0.5, w − 0.5] × [0.5, h − 0.5] (index space [0, w−1] × [0, h−1])
  before sampling. At 0° every sample sits on the pixel's own row centre, so rows never mix; at 90° columns never mix.
- **Rationale**: 16 filtered samples instead of 64 reads; clamping makes "samples stay inside the frame" a property
  of the positions, testable on the CPU, and repeats the border pixel past the edge (no outside colour).
- **Alternatives**: bilinear by hand from `read` like FX-006 (bit-exact against the CPU but 4× the reads); mirror
  addressing; a fade to zero blur at the border like FX-006 (the blur needs no fade: clamped samples never read
  outside the frame).

## FX-007-D4: Alpha and non-finite values

- **Decision**: premultiplied RGBA is averaged as a whole (colour ≤ alpha is kept by a convex combination). A
  non-finite own pixel passes through; a non-finite filtered sample is skipped and the remaining weights renormalised
  (none left → the own pixel), so NaN/Inf never spread.
- **Rationale**: FX-002 counts non-finite output; the blur must not multiply one bad pixel into 32.

## FX-007-D5: Value and ranges

- **Decision**: `DirectionalBlur { isEnabled, radius (0…0.02 of the shorter side, default 0.005, step 0.001),
  angleDegrees (0…180, default 0, step 15) }`. Active when enabled and radiusPx > 0. NaN radius → default, out of
  range → nearest bound; angle: finite values fold into [0, 180] (mod 180; exactly 180 kept), NaN/±Inf → 0.
- **Rationale**: the same shape and steps as FX-006's Amount and Angle; the axis has no sign, so 0…180 covers every
  direction once.

## FX-007-D6: Order and merge shape

- **Decision**: `OutputEffectKind.directionalBlur = "fx.directionalBlur"`, appended after `chromatic`; the standard
  order is Trails, Color, Chromatic split, Directional blur. Stored orders without it read with it last (FX-020's
  missing-kinds rule). In the walk, a non-neutral Color listed before an active blur is folded into the grade pass
  right before it, as for the split. Every new `switch` case is appended after FX-006's.
- **Rationale**: blurring after the split softens the fringes the same way a camera's motion blur would; appending
  keeps every stored order valid and the merge textual.

## FX-007-D7: Settings, scenes and storage

- **Decision**: keys `settings.directionalBlur.enabled` (Bool), `.radius` (Double), `.angle` (Double), written only
  when changed; the scene entry `fx.directionalBlur` with `radius` and `angle`. Keys go into FILE-005's included list,
  the privacy allow-list (`run_device_tests.py`), the UI-test reset and the app tests' key lists.
