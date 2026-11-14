# Data Model: FX-003 Color Grading

## ColorGrade (value, `Packages/Compositor`, plain Swift)

| Field | Range | Neutral | Step hint | Meaning |
|---|---|---|---|---|
| temperature | −1…1 | 0 | 0.01 | cool (−) to warm (+); unitless |
| lift | −0.1…0.1 | 0 | 0.005 | linear-light black level |
| gamma | 0.5…2 | 1 | 0.01 | mid-tones (> 1 brighter) |
| gain | 0.5…2 | 1 | 0.01 | overall multiplier |
| saturation | 0…2 | 1 | 0.01 | 0 grey, 2 doubled |

- `clamped`: NaN → neutral, out of range → nearest bound (every field).
- `isNeutral`: every field equals its neutral value (after clamping).
- `coefficients` → `ColorGradeCoefficients`: balance gains (3), lift scale and offset, exponent `1/γ`, gain,
  saturation, flags (bit 0 temperature, 1 lift, 2 gamma, 3 gain, 4 saturation). Flags 0 ⇔ neutral.
- `apply(_:)`: the reference on one linear premultiplied RGBA pixel (research FX-003-D2).

## ColorGradeCatalog (MOD-001 descriptors, target `ColorGradeParameters`)

IDs `effect.colorGrade.temperature`, `.lift`, `.gamma`, `.gain`, `.saturation`; group `effect.colorGrade`
"Color"; unit `.none`; kind `.continuous` with the
ranges, neutral defaults and step hints above; modulation `.continuousDefault`. IDs are permanent.

## ColorGradeSetting (app, `@Observable`, main actor)

Five Doubles stored under `settings.colorGrade.temperature|lift|gamma|gain|saturation`; read with
`ColorGrade.clamped` semantics (absent, non-number or NaN → neutral; out of range → clamped); `grade`
(the `ColorGrade`), `resetToNeutral()` (removes the five keys), `onChange` (the coordinator pushes the grade
to the compositor-backed hosts).

## Luminance ordering (FX-003-R4)

Each of lift, gamma and gain is the same non-decreasing function `f` on every channel
(`1 − L ≥ 0.9 > 0`, power with exponent `1/γ > 0` on values ≥ 0, `G > 0`, clamps at 0 non-decreasing). Output
luminance `Σ wᵢ f(xᵢ)` with `wᵢ > 0` is therefore non-decreasing when any input channel increases, and for
greys `f` is non-decreasing in the grey level.
