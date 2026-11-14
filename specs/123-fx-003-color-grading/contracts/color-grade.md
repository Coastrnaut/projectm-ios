# Contract: Color Grade in the Output Pass (FX-003)

## Compositor API (package `Compositor`)

- `public struct ColorGrade: Sendable, Equatable, Codable` — the five values (data-model.md), `neutral`,
  ranges as `static let …Range: ClosedRange<Double>`, `clamped`, `isNeutral`, `coefficients`, `apply(_:)`.
- `Compositor.colorGrade: ColorGrade` (default `.neutral`) and `SceneTransitionBus.colorGrade` — set between
  frames on the compositor's thread; the next encoded frame uses it in every output pass (screen, recording,
  capture) and in the flash guard. Setting it never invalidates CMP-013's caches.

## Shader (in `CompositorShaders`)

- `struct CMPGrade { float4 balance; float4 tone; float saturation; uint flags; uint pad0; uint pad1; }`
  (48 bytes; `tone` = (lift scale, lift offset, exponent, gain)).
- `cmp_grade(float4 c, constant CMPGrade &g)`: flags 0 → `c` unchanged; else sanitise, then the active
  operators in order temperature, lift, gamma, gain, saturation; alpha unchanged (sanitised).
- `cmp_display(c, g) = cmp_tone_map(cmp_grade(c, g))`.
- `cmp_output(composite [[texture(0)]], gain [[buffer(0)]], nonFinite [[buffer(1)]], grade [[buffer(2)]])` returns
  `float4(cmp_display(c, grade).rgb × clamp(gain, 0, 1), alpha)`.
- `cmp_flash_guard(…, grade [[buffer(3)]])` measures `cmp_display(sample, grade)`.

## Guarantees

1. Neutral grade: every output pixel is bit-identical to the FX-002 output (no grade).
2. Each control at neutral is an exact identity for its operator.
3. GPU output matches `ColorGrade.apply` then `ToneMap.map` within one 8-bit step (sRGB screen) or 0.002 (half
   float).
4. The guard's gain multiplies the graded, tone-mapped colour it measured.

## App (`projectM-iOS`)

- Keys: `settings.colorGrade.temperature`, `.lift`, `.gamma`, `.gain`, `.saturation` (Double).
- Settings → "Color": sliders `colorTemperatureSlider`, `colorLiftSlider`, `colorGammaSlider`,
  `colorGainSlider`, `colorSaturationSlider`; readouts `…Value`; button `colorResetButton` ("Reset to neutral",
  disabled at neutral).
