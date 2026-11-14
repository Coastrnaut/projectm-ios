# Contract: CMP-009 Luma Key

## K1 Keep factor (CPU reference = shader)

Input: a premultiplied linear colour (r, g, b, a), sanitised as the draw path does (non-finite → 0,
colour ≥ 0, alpha 0…1).

1. Straight colour c = a > 0 ? (r, g, b) / a : 0, each clamped to 0…1.
2. Encoded c′ = sRGB encode (c ≤ 0.0031308 ? 12.92·c : 1.055·c^(1/2.4) − 0.055).
3. Y′ = 0.2126·r′ + 0.7152·g′ + 0.0722·b′.
4. k = 1 if low ≤ Y′ ≤ high; else d = low − Y′ (below) or Y′ − high (above); k = s > 0 ? max(0, 1 − d/s) : 0.
5. keep = inverted ? k : 1 − k.

The drawn source is colour × opacity × shape coverage × gradient alpha × keep (all premultiplied).

## K2 Shader block

`CMPMask.luma` = (low, high, softness, mode) with mode 0 = no key, 1 = key, 2 = inverted key.
Mode 0 leaves the source untouched. A layer with a key and no masks is drawn through
`cmp_over_masked` (normal) or `cmp_blend` (other modes): no new pass or pipeline.

## L1 Scene form

```json
"composite": { "lumaKey": { "low": 0, "high": 0.1, "softness": 0.05, "invert": false } }
```

- Written only when set, every field, so decode → encode is byte-identical.
- Missing fields read the defaults of `LayerLumaKey.blackKey`; unknown keys are dropped
  (`droppedField`); out-of-range numbers clamped (`valueClamped`, one per field); low > high swapped
  (`valueClamped` at `…lumaKey`). Not an object: the usual type error of the decoder.
- Format version unchanged; older versions drop the field with `droppedField`.

## L2 Inspector

Section "Luma Key" after "Gradient": `layerControl.lumaKey` toggle; when on, ACC-005 sliders
`layerControl.lumaLow`, `layerControl.lumaHigh` (0…1, step 0.05), `layerControl.lumaSoftness`
(0…0.5, step 0.02) and the `layerControl.lumaInverted` toggle. Setting Low above High moves High to
Low (and the reverse). Read-only layers show the values as read-outs. Undo: one step per drag or
toggle, keys `layer.<kind>.<parameter>`.
