# Research: CMP-010 Color Key

## CMP-010-D1: Distance space

- **Decision**: the Rec. 709 Y′CbCr chroma plane of the displayed straight colour. Straight colour =
  premultiplied linear ÷ alpha (alpha ≤ 0 reads 0), each channel clamped 0…1, sRGB-encoded with the
  IEC 61966-2-1 curve (`LayerBlend.encode`, `cmp_key_encode`); Y′ = 0.2126·R′ + 0.7152·G′ + 0.0722·B′
  (CMP-009's weights); Cb = (B′ − Y′)/1.8556, Cr = (R′ − Y′)/1.5748; d = √((Cb − Cb_k)² + (Cr − Cr_k)²)
  with (Cb_k, Cr_k) the key colour's chroma (the key is given as displayed sRGB, so it is not encoded
  again).
- **Rationale**: chroma keyers work in Cb/Cr because brightness changes of one hue (shading on a
  backdrop) should matter less than hue changes; the encoded values match what the user picks on
  screen; the luma step is shared with CMP-009. Fixture distances to pure green (Cb −0.385, Cr −0.454):
  red 0.99, blue 0.89, white 0.59, skin sRGB (0.87, 0.67, 0.55) 0.64, dark green sRGB (0, 0.3, 0) 0.42 —
  all beyond the default tolerance 0.2 + feather 0.1.
- **Alternatives**: OKLab ΔE (cube roots per pixel and a lightness weight to tune; no acceptance gain);
  RGB Euclidean (mixes brightness and hue); hue angle only (unstable for near-greys).

## CMP-010-D2: Keep factor

- **Decision**: keyed k = 1 for d ≤ tolerance; with feather f > 0, k = clamp(1 − (d − tolerance)/f, 0, 1);
  f = 0 gives k = 0 beyond. keep = 1 − k. It multiplies the premultiplied colour and alpha with the shape
  coverage, gradient alpha and luma keep.
- **Rationale**: as CMP-009-D2: strictly monotonic and exactly reproducible on the CPU; a kept pixel's
  straight colour is unchanged (acceptance: unrelated colours unchanged).
- **Alternatives**: smoothstep (harder exact comparison); spill suppression (recolours kept pixels;
  out of scope per Clarifications); invert (not needed by the row).

## CMP-010-D3: Shader placement

- **Decision**: one `float4 chroma` row appended to `CMPMask` (432 bytes, `setFragmentBytes`):
  (Cb_k, Cr_k, tolerance, 1 + feather), w = 0 meaning no key, so the all-zero `MaskBlock.none` stays
  "no key" without a fifth float. Keyed layers take the existing masked routes (`cmp_over_masked` for
  normal, `cmp_blend` otherwise). Cb_k and Cr_k are computed on the CPU once per block.
- **Rationale**: no new pipeline or pass (CMP-010-R7), proven by `maskedDraws`/`blendDraws`; one row as
  CMP-009 did.
- **Alternatives**: a separate key pass (extra pass); a mode float in another row (a second new row).

## CMP-010-D4: Picker colour

- **Decision**: SwiftUI `ColorPicker(supportsOpacity: false)`; the picked `Color` is resolved through
  `UIColor.getRed(_:green:blue:alpha:)`, which returns extended sRGB components; each is clamped to 0…1
  and rounded to 1/1000 so stored values stay short and round-trip exactly. Opacity is ignored.
- **Rationale**: public API; P3 picks map to the nearest sRGB value the compositor can match.
- **Alternatives**: three RGB sliders (more controls, less direct); an eyedropper on the picture (needs
  read-back from the live render; out of scope).
