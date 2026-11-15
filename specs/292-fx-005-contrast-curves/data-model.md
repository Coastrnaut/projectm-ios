# Data Model: FX-005 Contrast Curves

## ContrastCurve (enum, String raw values)

| Case | Raw | Meaning |
|---|---|---|
| `linear` | `linear` | Neutral: the curve is skipped (default, unknown names) |
| `sCurve` | `sCurve` | Two-sided power around 0.18 (research FX-005-D3) |
| `filmic` | `filmic` | Toe ∘ shoulder blended by strength (D4) |

## ColorGrade (FX-003) gains

| Field | Type | Range | Default | Read rule |
|---|---|---|---|---|
| `contrast` | `ContrastCurve` | 3 cases | `linear` | missing/unknown → `linear` |
| `contrastStrength` | Double | 0…1 | 0.5 | NaN → 0.5, out of range → nearest bound |

Neutral (no curve flag): `contrast == .linear` or `contrastStrength == 0`.

## Storage

- UserDefaults: `settings.colorGrade.contrast` (String), `settings.colorGrade.contrastStrength` (Double).
- Scene `effects[]` entry `fx.grade`, `parameters.contrast` (string), `parameters.contrastStrength` (number).
- MOD-001: `effect.colorGrade.contrast` (enumeration, default `linear`, discrete manual),
  `effect.colorGrade.contrastStrength` (continuous 0…1, default 0.5, step 0.01).
