# Contract: layer blend modes (CMP-004)

Extends CMP-001's layer contract (`specs/029-cmp-001-unified-layer-protocol/contracts/layer-source.md`)
and CMP-003's opacity contract. ADR-0037 records the colour space.

## Names

`normal`, `add`, `screen`, `multiply`, `overlay`, `difference` — exact, lower case. They are
`LayerBlendMode`'s raw values and the scene format's `composite.blend` values.

## Inputs (per pixel)

- Backdrop: the composite of every layer below, linear light, premultiplied: (cb, αb).
- Source: the layer's picture, sanitized as for normal (non-finite → 0, colour ≥ 0, alpha clamped to
  0…1), sampled through its CMP-005 transform, then multiplied by its CMP-003 opacity o (0…1):
  (cs, αs) = o · picture.

## Steps

1. Straight colours: Cb = cb / αb if αb > 0, else 0; Cs = cs / αs if αs > 0, else 0.
2. Clamp each to 0…1 and encode with sRGB: E(x) = 12.92·x for x ≤ 0.0031308, else
   1.055·x^(1/2.4) − 0.055.
3. Blend function per channel on the encoded values Eb, Es:

   | Mode | B(Eb, Es) |
   |---|---|
   | normal | Es |
   | add | min(1, Eb + Es) |
   | screen | Eb + Es − Eb·Es |
   | multiply | Eb·Es |
   | overlay | Eb ≤ 0.5: 2·Eb·Es; else screen(Es, 2·Eb − 1) |
   | difference | abs(Eb − Es) |

4. Decode: D(y) = y / 12.92 for y ≤ 0.04045, else ((y + 0.055) / 1.055)^2.4.
5. Source-over in linear premultiplied:
   co = cs·(1 − αb) + cb·(1 − αs) + αs·αb·D(B);
   αo = αs + αb·(1 − αs).

## Drawing rules

- `normal` layers are drawn with the fixed-function "over" (one, oneMinusSourceAlpha) exactly as
  before CMP-004; stacks of only normal layers are bit-identical to CMP-003/CMP-005 output.
- Every other mode reads the backdrop in the shader (two pooled composite textures, swapped per
  mode layer). Opacity exactly 0 skips the layer in every mode (co = cb, αo = αb).
- A mode change at `apply` is shown from the next frame; no layer is created or prepared.
- The composite flash guard and the output pass run on the finished composite, as before.

## Tolerance (acceptance)

GPU against this contract evaluated in `Double` on the same half-float inputs: ≤ 1e-3 per channel in
the `rgba16Float` composite; ≤ 1/255 per channel in an 8-bit sRGB output (reference encoded and
rounded to 8 bits).

## Scene format

Version 1 unchanged. The six names are drawn without a warning. Any other string is kept verbatim
(decode → encode, and load → capture while the layer is drawn as normal), drawn as normal and reported
as `unsupportedBlendMode` (warning; SCN-012 "values adjusted", note).
