# Data Model: SHD-006 Noise Editor

## Noise Flow parameters (`material.noiseFlow.<id>`; slot = position)

| Slot | ID | Kind | Range | Step | Default | Note |
|---|---|---|---|---|---|---|
| 0 | scale | float | 1…16 | 0.1 | 4 | unchanged |
| 1 | speed | float | 0…1 | 0.01 | 0.08 | unchanged |
| 2 | octaves | int | 1…**8** | 1 | 3 | widened from 1…5 |
| 3 | tint | color | — | — | (0.10, 0.35, 0.45, 1) | unchanged |
| 4 | brightness | float | 0…1 | 0.01 | 0.6 | unchanged |
| 5 | audioReactivity | float | 0…1 | 0.01 | 0.25 | unchanged |
| 6 | seed | int | 0…65535 | 1 | 0 | new |
| 7 | lacunarity | float | 1.5…3.5 | 0.01 | 2.03 | new |
| 8 | gain | float | 0.2…0.8 | 0.01 | 0.5 | new |
| 9 | warpAmount | float (cells) | 0…4 | 0.05 | 0.8 | new |
| 10 | warpFrequency | float (× scale) | 0.25…4 | 0.05 | 1 | new |

## NoiseTextureSettings (plain Swift)
`seed: UInt32, octaves: Int, lacunarity: Float, gain: Float, warpAmount: Float, warpFrequency: Float, scale: Float`;
made from `MaterialParameterValues` of Noise Flow; `NoiseTextureReference.value(at:phase:settings:lite:)` → 0…1.

## NoiseSeedSequence
`counter: UInt32` (starts at 1); `next(after current: Int) -> Int` in 0…65535, never `current`.

## Stored editor values (UserDefaults `settings.noiseEditor.values`)
JSON object, sorted keys: parameter name → MOD-001 `ParameterValue` encoding. Missing names = defaults.
