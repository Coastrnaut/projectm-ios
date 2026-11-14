# Contract: the output tone map (FX-002)

## C1 Mapping (`ToneMap.map`, `cmp_tone_map`)

Input: one linear premultiplied RGBA composite pixel, any float values. Output: RGBA in 0…1, never NaN.

1. Sanitise: a colour channel that is NaN, ±Inf or negative becomes 0; alpha NaN/±Inf becomes 0, then
   alpha is clamped to 0…1.
2. m = max(r, g, b). m ≤ 1: the sanitised pixel is the output (bit-identical for finite in-range input).
3. Y = 0.2126 r + 0.7152 g + 0.0722 b. Y ≥ 1: output (1, 1, 1, α).
4. Otherwise s = (1 − Y) / (m − Y); output rgb = clamp(Y + s·(c − Y), 0, 1), alpha α, computed as the equal
   1 − s·(m − c) so the largest channel is exactly 1 in float (no dip below the m ≤ 1 branch's 1).

Guarantees: monotonic along every colour ray of finite values; output luminance = min(Y, 1); hue kept.

## C2 Pipeline position

composite (rgba16Float) → flash guard measures `cmp_tone_map(sample)` → output pass writes
`float4(cmp_tone_map(c).rgb × clamp(gain, 0, 1), cmp_tone_map(c).a)` into the target. Same shader for:
`Compositor.composite(into:)` (screen, external display), `Compositor.encodeOutput(into:)` (REC-003),
the REC-001 capture, `SceneTransitionBus.composite(into:)` and `encodeOutput(into:)`.

## C3 Diagnostics

`Compositor.nonFiniteOutputPixels` and `SceneTransitionBus.nonFiniteOutputPixels` (`UInt32`, cumulative):
composite pixels with a non-finite channel met by the screen pass of completed frames. Recording and
capture passes do not count. Read after the command buffer completed for an exact value.

## C4 Unchanged

Layer passes, blend modes, the flash envelope's rule and parameters, output formats, capture conversion,
recording and the public API apart from the two new read-only properties.
