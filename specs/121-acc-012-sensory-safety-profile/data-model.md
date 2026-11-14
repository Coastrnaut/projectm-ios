# Data Model: ACC-012 Sensory Safety Profile

## SensorySafetyPreset (FlashSafety)

`standard | reduced | strict | custom`; raw values stored. Unknown stored value → `standard`.

## SensorySafetyLimits (FlashSafety)

| Field | Range | Standard | Reduced | Strict |
|---|---|---|---|---|
| `flashesPerSecond` (Int) | 1…3 | 3 | 2 | 1 |
| `riseLimitPerSecond` (Double?) | nil or 0.05…1.0 | nil | 0.25 | 0.10 |
| `intensityLimit` (Double) | 0…1 | 1.0 | 0.5 | 0.25 |

`init` clamps each field (NaN intensity → 1; NaN or ≤ 0 rise → nil). `stricter(than:)` takes the per-field
minimum (nil rise = +∞). `flashConfiguration` = `FlashEnvelopeConfiguration(transitionBudget: 2f,
riseRatePerSecond: r)`.

## SensorySafetyProfile (FlashSafety)

`preset` + `custom: SensorySafetyLimits` (initially Reduced's). `limits` = the preset's table row, or
`custom` for Custom.

## SafetyClamp (FlashSafety)

Built from a profile and the effective Reduce flashing setting. Fields: `limits` (effective),
`reducesFlashing` (Bool). Derived: `flashConfiguration`, `flashLimitsOverride` (nil when equal to
`forReduceFlashing(reducesFlashing)`), `isIdentity`. Functions: `intensity(_:maximum:)`,
`modulated(manual:modulated:)`, `speed(_:cap:)`. `SafetyClamp.standard` = Standard, Reduce flashing off.

## Storage (app, `SensorySafetySetting`)

| Key | Type | Absent / invalid |
|---|---|---|
| `settings.sensorySafety.profile` | String | `standard` |
| `settings.sensorySafety.flashesPerSecond` | Int | Reduced's 2 |
| `settings.sensorySafety.riseLimit` | Double (0 = none) | Reduced's 0.25 |
| `settings.sensorySafety.intensityLimit` | Double | Reduced's 0.5 |

All four: in `AppSettings.allKeys` (cleared by `-uitestResetNotice`), `ALLOWED_KEYS` and
`LibrarySettingsPolicy.includedKeys`. State transitions: choosing Custom the first time copies the previous
preset's limits into the custom keys.
