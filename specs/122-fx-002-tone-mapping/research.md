# Research: FX-002 Tone Mapping

## FX-002-D1: the operator

**Decision**: per pixel, after sanitising (FX-002-R2), with m = max(r, g, b) and the Rec. 709 / WCAG
luminance Y = 0.2126 r + 0.7152 g + 0.0722 b:

1. m ≤ 1 → unchanged;
2. Y ≥ 1 → white (1, 1, 1);
3. otherwise s = (1 − Y) / (m − Y) and out = Y + s · (c − Y) per channel, then clamped to 0…1 (rounding only).
   Both implementations compute the equal form 1 − s · (m − c): the GPU gradient test found that
   Y + s · (c − Y) gives 0.99999… for the largest channel in float, which rounds to the half 0.99951 just
   after the identity branch's exact 1 (a one-ulp order violation in the half-float output); 1 − s · 0 is exactly 1.

Step 3 is a straight line from the pixel's grey (Y, Y, Y) toward the pixel; s < 1 is the largest fraction
that keeps the largest channel at 1. Because the weights sum to 1, the luminance of (c − Y) is 0, so the
output luminance equals Y: luminance and hue (the direction from grey) are kept and only saturation drops.
m > 1 > Y gives m − Y > 0, so the division never divides by zero and needs no epsilon.

**Rationale**: identity on every in-range pixel keeps every golden and every current frame bit-identical
(FX-002-R3, R10); over-range colour keeps its hue instead of the 8-bit target's per-channel clip, which
turns orange into yellow (audit); white is the natural limit of light.

**Alternatives considered**: (a) a soft knee at 0.8 with an exponential or extended-Reinhard shoulder:
darkens in-range highlights (white → about 0.93 with a C¹ shoulder whose asymptote is 1) and changes every
golden; (b) ACES fitted: tints and darkens all mid-tones, against VIII (upstream fidelity); (c) scaling
the colour by 1/m (hue-preserving clamp): keeps hue but loses luminance badly, e.g. (4, 0.9, 0.9) → (1,
0.225, 0.225), a bright pink turning dark red; (d) per-channel clamp in the shader: today's look without
the format dependence, still hue-shifting.

## FX-002-D2: proof of monotonicity

Let c = t·v with v ≥ 0 fixed (a colour ray), m_v = max v, Y_v = Y(v), t ≥ 0. Output channel i as a function
of t:

- region A, t·m_v ≤ 1: o_i = t·v_i, derivative v_i ≥ 0;
- region B, t·m_v > 1 and t·Y_v < 1: o_i = t·Y_v + (1 − t·Y_v)(v_i − Y_v)/(m_v − Y_v) (the t cancels in
  s·(c − Y)), derivative Y_v·(m_v − v_i)/(m_v − Y_v) ≥ 0, since v_i ≤ m_v and Y_v < m_v in this region
  (Y_v = m_v only for grey, which goes from A straight to C);
- region C, t·Y_v ≥ 1: o_i = 1, constant.

o_i is continuous at both boundaries (s = 1 at t·m_v = 1, so B starts at t·v_i; s = 0 at t·Y_v = 1, so B
ends at 1), so it is a continuous piecewise function with non-negative slopes: non-decreasing in t. The
final clamp is monotonic. Output luminance is min(Y, 1) in every region and Y increases with every input
channel (positive weights), so output luminance never decreases when any input channel increases. Not
claimed: that every output channel is non-decreasing in every input channel (raising one channel can lower another channel's
output in region B, because the pixel desaturates). Tests: the reference over a ray grid and 10,000 random
colours (FX-002-S5), the GPU gradient (S1).

## FX-002-D3: order of tone map and flash limiter

**Decision**: tone map, then measure, then gain: the composite flash guard runs each of its 4,096 samples
through the same `cmp_tone_map` before computing luminance and redness; the output pass writes
gain × tone_map(composite). Since the guard's gain scales its measured levels linearly, the levels it
commits are exactly what is shown.

**Rationale**: FX-019 must judge what the user sees. Measuring the raw composite counts 1 → 16 as a huge
luminance step although the screen shows white both times (false dimming), and its luminance can exceed
1. Applying the gain before the tone map would also break the linear-gain model of the guard.

**Alternatives considered**: gain before tone map (non-linear: the guard's closed-form gain would no longer
give the shown level); a separate measurement pass on the output texture (a new pass, and the 8-bit
targets would need read access).

**Coordination**: the guard edit is one line inside its shader string plus the spliced function; the
envelope rule, its parameters and `FlashEnvelopeConfiguration` (which ACC-012 changes) are untouched.

## FX-002-D4: counting non-finite pixels

**Decision**: `cmp_output` takes a `device atomic_uint *` at buffer index 1 and adds 1 (relaxed) when any
channel of the composite pixel is NaN or infinite. The compositor and the bus each own a 4-byte shared
counter buffer bound for the screen pass, and a 4-byte sink buffer bound for recording and capture passes
(not counted twice, clarify session). `nonFiniteOutputPixels` reads the counter (like `lastFlashGain`).
The branch costs nothing when no pixel is non-finite.

**Alternatives considered**: counting in the flash guard (only a 4,096-point sample of the frame); a
compute pass (a new pass).

## FX-002-D5: no setting

**Decision**: no user setting and no UserDefaults key. In-range pixels are untouched, so turning the stage
off would only bring back format-dependent clipping and NaN pass-through. Nothing to add to
`ALLOWED_KEYS` or FILE-005's `LibrarySettingsPolicy.includedKeys`.

## FX-002-D6: tolerances and test inputs

The reference gradient is 256 columns from 0 to 16 in linear light on four rows: grey, orange (1, 0.5,
0.25), blue (0.2, 0.4, 1) and a saturated red (1, 0.05, 0.05), all at alpha 1, rendered by a test layer
through the real compositor; the special values (NaN, ±Inf, negatives, alpha NaN and 2) go through the real
`cmp_output` on a hand-filled composite, because every layer pass already sanitises them. GPU versus
reference: one 8-bit step for `bgra8Unorm_srgb` (the reference is sRGB-encoded by
`FrameColorConversion.linearToSRGB`), 0.002 for `rgba16Float`.
