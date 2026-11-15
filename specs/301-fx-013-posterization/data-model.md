# Data Model: FX-013 Posterization

## ColorGrade (FX-003, extended)

| Field | Type | Range | Default | Neutral |
|---|---|---|---|---|
| `posterize` | Bool | — | false | false (step skipped) |
| `posterizeLevels` | Int | 2…32 (clamped) | 6 | any (ignored while off) |
| `posterizeDither` | Bool | — | false | any (ignored while off) |

Codable keys appended (`posterize`, `posterizeLevels`, `posterizeDither`); missing → defaults.

## ColorGradeCoefficients (extended)

- `poster: SIMD4<Double>` = (n = L − 1, 1/n, 0, 0).
- Flags: `posterizeFlag` 64 when `posterize`; `ditherFlag` 128 when `posterize && posterizeDither`.

## GradeBlock / CMPGrade (shader)

`balance` 0, `tone` 16, `hue` 32, `saturation` 48, `flags` 52, pads, `contrast` 64, **`poster` 80**; size 96.

## Storage

| Where | Key | Type | Missing / invalid |
|---|---|---|---|
| UserDefaults | `settings.colorGrade.posterize` | Bool | off |
| UserDefaults | `settings.colorGrade.posterizeLevels` | number | 6; rounded, clamped 2…32 |
| UserDefaults | `settings.colorGrade.posterizeDither` | Bool | off |
| Scene `fx.grade` | `posterize`, `posterizeLevels`, `posterizeDither` | bool, number, bool | off, 6, off (warning when malformed) |
| MOD-001 | `effect.colorGrade.posterize`, `.posterizeLevels`, `.posterizeDither` | boolean, integer, boolean | defaults |

All three keys are in `ColorGradeSetting.allKeys` (reset, UI-test reset, FILE-011 erase), FILE-005
`LibrarySettingsPolicy.includedKeys` and `ALLOWED_KEYS`.
