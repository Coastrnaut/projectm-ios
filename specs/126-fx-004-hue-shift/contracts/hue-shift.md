# Contract: Hue Shift in the Colour Grade (FX-004)

Extends FX-003's contract (`specs/123-fx-003-color-grading/contracts/color-grade.md`).

## Compositor API

- `ColorGrade.hue: Double` (degrees), `hueRange = -180...180`, `hueStep = 1`; `init(…, saturation:, hue: = 0)`.
- `ColorGradeCoefficients.hueMatrix: SIMD4<Double>`, `hueFlag: UInt32 = 32`.

## Shader

- `CMPGrade` gains `float4 hue` after `tone` (64 bytes).
- `cmp_grade`: after saturation, when `(flags & 32u) != 0u`, the hue step of research FX-004-D1 to D3.

## Guarantees

1. Hue 0: the flag is off; output bit-identical to FX-003 for any other controls (and to bypass at neutral).
2. Greys (r = g = b ≥ 0) leave the hue step bit-identical, for every angle.
3. Luminance is kept by the hue step (to rounding), including through the gamut step.
4. GPU output matches the reference (then `ToneMap.map`) within one 8-bit step (sRGB) or 0.002 (half float);
   the red patch matches research FX-004-D6.
5. The flash guard measures the shifted colour.

## App

- Key `settings.colorGrade.hue` (Double), in `ColorGradeSetting.allKeys`, the FILE-005 included keys and the
  privacy allow-list.
- Settings → Color: slider `colorHueSlider` (label "Hue"), readout `colorHueSliderValue`; "Reset to neutral"
  includes it.
- MOD-001 ID `effect.colorGrade.hue`.
