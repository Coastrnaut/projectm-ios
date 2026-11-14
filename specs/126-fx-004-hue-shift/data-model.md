# Data Model: FX-004 Hue Shift

## ColorGrade (FX-003 value, `Packages/Compositor`) — new field

| Field | Range | Neutral | Step hint | Meaning |
|---|---|---|---|---|
| hue | −180…180 | 0 | 1 | degrees around the grey axis; +120 maps red's hue to green's |

- `clamped`: NaN → 0, out of range (±Inf) → nearest bound.
- Decoding: a missing `hue` key decodes as 0.
- `coefficients`: `hueMatrix` (T00, T01, T10, T11; research FX-004-D1) and flag bit 5 (`hueFlag = 32`) when
  hue ≠ 0.
- Operator order: temperature, lift, gamma, gain, saturation, hue (D4).

## Shader block `CMPGrade` (64 bytes)

`float4 balance; float4 tone; float4 hue; float saturation; uint flags; uint pad0; uint pad1;`

## ColorGradeCatalog

Adds `effect.colorGrade.hue` ("Hue (degrees)", unit `.degrees`, −180…180, default 0, step 1,
`.continuousDefault`). IDs are permanent.

## ColorGradeSetting (app)

Adds `hue` stored under `settings.colorGrade.hue` (read rule as the other five; reset removes it). Readout
`hueText`: "+30°", "0°", "−120°".
