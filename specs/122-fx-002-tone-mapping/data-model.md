# Data Model: FX-002 Tone Mapping

No stored data. Values only.

## ToneMap (plain Swift, `Compositor` target)

- `ToneMap.Pixel` = `SIMD4<Double>`, linear premultiplied RGBA (any values, including NaN and ±Inf).
- `ToneMap.luminanceWeights` = (0.2126, 0.7152, 0.0722).
- `ToneMap.sanitize(_:) -> Pixel`: non-finite or negative colour channels → 0; alpha non-finite → 0, then
  clamped to 0…1.
- `ToneMap.map(_:) -> Pixel`: sanitize, then FX-002-D1 steps 1-3. Output colour and alpha in 0…1, never NaN.
- `ToneMap.isNonFinite(_:) -> Bool`: any channel NaN or infinite (what the screen pass counts).

## Output pass state (Metal, per `Compositor` and per `SceneTransitionBus`)

- counter buffer: 4 bytes, shared, starts at 0; incremented by the screen pass per non-finite composite
  pixel; read as `nonFiniteOutputPixels: UInt32` (cumulative, wraps at 2³²).
- sink buffer: 4 bytes, shared, bound for recording and capture passes; never read.

## Relationships

- `cmp_tone_map` (Metal) ≡ `ToneMap.map` (Swift), compared by tests.
- Composite flash guard sample = `cmp_tone_map(composite sample)`; output pixel = gain × `cmp_tone_map(composite)`.
