# Contract: CMP-010 Color Key

## C1 Keep factor (CPU reference = shader)

Input: a premultiplied linear colour (r, g, b, a), sanitised as the draw path does (non-finite → 0,
colour ≥ 0, alpha 0…1).

1. Straight colour c = a > 0 ? (r, g, b) / a : 0, each clamped to 0…1.
2. Encoded c′ = sRGB encode (c ≤ 0.0031308 ? 12.92·c : 1.055·c^(1/2.4) − 0.055).
3. Y′ = 0.2126·r′ + 0.7152·g′ + 0.0722·b′; Cb = (b′ − Y′)/1.8556; Cr = (r′ − Y′)/1.5748.
4. The key colour's (Cb_k, Cr_k) from its stored sRGB values by step 3 (no encode).
5. d = √((Cb − Cb_k)² + (Cr − Cr_k)²).
6. k = 1 if d ≤ tolerance; else k = feather > 0 ? max(0, 1 − (d − tolerance)/feather) : 0.
7. keep = 1 − k.

The drawn source is colour × opacity × shape coverage × gradient alpha × luma keep × colour keep (all
premultiplied).

## C2 Shader block

`CMPMask.chroma` = (Cb_k, Cr_k, tolerance, 1 + feather); w = 0 means no key and leaves the source
untouched. A layer with a key and no other mask is drawn through `cmp_over_masked` (normal) or
`cmp_blend` (other modes): no new pass or pipeline. `CMPMask` is 432 bytes.

## C3 Scene form

```json
"composite": { "colorKey": { "red": 0, "green": 1, "blue": 0, "tolerance": 0.2, "feather": 0.1 } }
```

- Written only when set, every field, so decode → encode is byte-identical.
- Missing fields read `LayerColorKey.greenKey`'s; unknown keys are dropped (`droppedField`);
  out-of-range numbers clamped (`valueClamped`, one per field). Not an object or a non-number field:
  the decoder's usual type error.
- Format version unchanged; older versions drop the field with `droppedField`.

## C4 Inspector

Section "Color Key" after "Luma Key": `layerControl.colorKey` toggle; when on, a `ColorPicker` with the
accessible name "Key Color" (`layerControl.colorKeyColor`, no opacity), ACC-005 sliders
`layerControl.colorTolerance` (0…1, step 0.02) and `layerControl.colorFeather` (0…0.5, step 0.02).
Turning it on gives `greenKey`. Read-only layers show the values as read-outs (the colour as
`#RRGGBB`). Undo: one step per toggle, per drag (`layer.<kind>.colorTolerance`,
`layer.<kind>.colorFeather`) and per colour choice (picker updates coalesce under
`layer.<kind>.colorKeyColor`; label "<Layer> Key Color #RRGGBB").
