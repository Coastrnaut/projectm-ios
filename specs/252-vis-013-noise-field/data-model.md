# Data Model: VIS-013 Noise Field

## NoiseFieldConfiguration (pure Swift)

| Field | Type | Range / default |
|---|---|---|
| frequency | Double (cells across the shorter side) | 1…16, default 4 (settings use 2/4/8) |
| octaves | Int | 1…6, default 4 |
| seed | UInt32 | 0…65535, default 1301 |
| reduceMotion | Bool | false |
| palette | VisualPalette | spectrum |

Constants: lacunarity 2.03, gain 0.5, base warp 0.5, band warp 1.0, brightness 0.5…0.8, smoothing τ 0.25 s,
drift 0.12 cells/s, Reduce Motion factors 0.5.

## NoiseFieldDrive (pure Swift)

State: warp, brightness, phase, anchor time, has-frame flag. `advance(groups:timeNanoseconds:frameDuration:)`;
`reset()` returns to silence (warp 0.5, brightness 0.5, phase 0).

## App settings

| Key | Values | Fallback |
|---|---|---|
| `settings.visual` | adds `noiseField` | — |
| `settings.noiseField.frequency` | `low`/`medium`/`high` | medium |
| `settings.noiseField.octaves` | Int 1…6 | 4 |
| `settings.noiseField.seed` | Int 0…65535 | 1301 |
