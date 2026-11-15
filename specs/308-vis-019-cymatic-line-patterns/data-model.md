# Data Model: VIS-019 Cymatic Line Patterns

## CymaticBandRange (enum, String raw value; stored)
`all` (default), `low`, `mid`, `high`. `range(count:)` → half-open band index range (all: 0..<N; thirds as VIS-007:
g = N / 3 → low 0..<g, mid g..<2g, high 2g..<N). `title`: "All", "Low", "Mid", "High".

## CymaticSettings (struct, Equatable, Sendable)
`bands: CymaticBandRange`. `NoiseFieldConfiguration.cymatic: CymaticSettings?` (nil = mode off).

## CymaticMode (struct)
`n`, `m` (wave numbers, Float), `sign` (±1), `paletteT`. `CymaticField.modes`: index 0 = rest (1,1,+; t 0.5), 1…8 = driven
(1,2,−) (1,3,+) (2,3,−) (1,4,−) (2,4,+) (3,4,−) (2,5,+) (3,5,−) with t = (k − 1) / 7.

## CymaticState (CymaticDrive, value type, Equatable)
- `weights: SIMD16<Float>` (lanes 0…8 used; others 0), each in 0…1; initial rest = 1.
- `target: Int` (0 = rest, 1…8 driven).
- `amplitude: Float` 0…1; `amplitudeTarget`.
- `lastNanoseconds: UInt64?`; `reduceMotion: Bool`.
- Invariants: Σ weights > 0; all values finite; `isAtRest` ⇔ weights == rest one-hot && amplitude == 0.

## Uniform block (buffer 1, 40 floats)
`modes[9]: float4(n, m, sign, weight)`, then `amplitude`, `width`, `paletteT`, `fill`.
