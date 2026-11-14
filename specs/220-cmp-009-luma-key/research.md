# Research: CMP-009 Luma Key

## CMP-009-D1: Luma formula and space

- **Decision**: Y′ = 0.2126·R′ + 0.7152·G′ + 0.0722·B′ where R′G′B′ are the sRGB-encoded straight colour
  channels (premultiplied linear ÷ alpha, alpha ≤ 0 reads colour 0, each clamped 0…1), encoded with
  the IEC 61966-2-1 curve already used by `LayerBlend` and `cmp_encode`.
- **Rationale**: the compositor works in linear premultiplied half floats; users judge "dark" on the
  displayed picture. Encoded luma puts mid-grey near 0.5 and a black key's threshold at a usable 0.1.
  Reusing the blend modes' encode keeps one curve in the shaders.
- **Alternatives**: linear luminance Y (dark thresholds crowd near 0); max channel (not luma);
  BT.601 weights (the project already uses Rec. 709 weights in the grade and tone map).

## CMP-009-D2: Keep factor

- **Decision**: k(Y′) = 1 inside low…high; outside, with softness s > 0, k = clamp(1 − d/s, 0, 1)
  where d is the distance to the nearer end; s = 0 gives k = 0 outside. keep = 1 − k (inverted: k).
  It multiplies the premultiplied colour and alpha (with the shape coverage and gradient alpha).
- **Rationale**: linear ramp is strictly monotonic on each side and exactly reproducible on the CPU;
  multiplying premultiplied values leaves a kept pixel's straight colour unchanged.
- **Alternatives**: smoothstep (CMP-007's feather; harder exact comparison near 0/1, no visible gain
  at softness ≤ 0.5); keying colour to black instead of transparency (not the row).

## CMP-009-D3: Shader placement

- **Decision**: one `float4 luma` row appended to `CMPMask` (416 bytes, `setFragmentBytes`); the
  layer is routed through the existing masked paths when a shape, gradient or key is set;
  `cmp_luma_keep` reads the sanitised sample before opacity.
- **Rationale**: no new pipeline or pass (CMP-009-R7); the draw counters `maskedDraws`/`blendDraws`
  prove it, as in CMP-008.
- **Alternatives**: a separate key pass (an extra render pass per layer); a function constant
  specialisation (a new pipeline).

## CMP-009-D4: Bilinear sampling of transformed layers

- **Decision**: the key reads the bilinear sample (filtered premultiplied colour, then ÷ alpha).
- **Rationale**: premultiplied filtering avoids dark fringes; it is the colour actually drawn.
