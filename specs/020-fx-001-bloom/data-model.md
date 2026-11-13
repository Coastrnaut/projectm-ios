# Data Model: FX-001 Bloom

All types are in `Packages/VisualGenerators`, target `VisualEffects`, unless marked otherwise.
Types without Metal build on Linux; Metal types are behind `#if canImport(Metal) && !VISUAL_NO_METAL`.

## BloomParameters (struct, Sendable, Equatable, Codable)

| Field | Type | Range (clamped) | Default | Shown in Settings |
|---|---|---|---|---|
| enabled | Bool | — | false | "Glow" toggle |
| intensity | Float | 0…1 | 0.5 | "Intensity" slider |
| radius | Float (fraction of the output's shorter side) | 0.005…0.06 | 0.02 | "Radius" slider |
| threshold | Float (linear max-channel brightness) | 0.1…1 | 0.7 | "Threshold" slider |
| knee | Float (fraction of the threshold) | 0…1 | 0.5 | no |

`clamped()`: out of range → nearest bound; NaN → default. Decoding clamps. `isPassThrough` =
`!enabled || intensity == 0` (after clamping). `kneeWidth = knee · threshold`.
`contribution(ofMaxChannel:)` and `thresholded(_: LinearColor)` implement research FX-001-D3 step 1
on the CPU (the same formula as the shader).

## BloomPlan (struct, Sendable, Equatable) — derived per output size

| Field | Meaning |
|---|---|
| width, height | output pixels (≥ 1) |
| downsample (D) | 2, 4 or 8 |
| blurRadius (R) | 1…16 reduced texels |
| reducedWidth, reducedHeight | ⌈W/D⌉, ⌈H/D⌉ |
| weights | R + 1 normalized half-kernel weights (w0 + 2·Σ w_i = 1), σ = R/2 |
| haloExtent (E) | (R + 2) · D pixels, Chebyshev distance |

`static let maxTapsPerSide = 16`. Pure function of (parameters, width, height).

## BloomLuminanceModel (struct, conforms to `FrameLuminanceTransfer`)

`outputLuminance(ofFlatColor c) = Y(c) + k · Y(P(c))` when not pass-through, else `Y(c)`.

## FrameLuminanceTransfer (protocol, target `VisualGenerators`)

`func outputLuminance(ofFlatColor: LinearColor) -> Double`: the mean relative luminance a flat
region of this linear premultiplied pixel color contributes after the downstream effects, per unit
of its area (an upper bound). Identity = `Y(c)`.

## EffectIdentifier (struct, Sendable, Hashable, Codable, RawRepresentable String)

Stable IDs, never reused: `fx.bloom` (FX-001). Later rows add `fx.tonemap`, `fx.grade`, …

## EffectDescription (enum, Sendable, Equatable, Codable)

`.bloom(BloomParameters)`, `.unknown(EffectIdentifier)` (decoded from an unknown id; kept, skipped
when building a chain). JSON: `{"id": "fx.bloom", "parameters": {…}}`.

## EffectChainDescription (struct, Sendable, Equatable, Codable)

`formatVersion: Int` (current 1; a larger value fails decoding with
`EffectChainDescriptionError.unsupportedVersion`), `effects: [EffectDescription]` (ordered, at most
16; more fails decoding). `activeEffects` = the known, non-pass-through entries in order.

## PostProcessEffect (protocol, Metal)

See [contracts/post-process-effect.md](contracts/post-process-effect.md).

## BloomEffect (final class, Metal) and EffectChain (final class, Metal)

`BloomEffect(device:pixelFormat:parameters:)` throws `VisualGeneratorError`; `parameters` settable
(recomputes the plan's weights, no GPU work); `plan` (last prepared). `EffectChain(device:pixelFormat:
effects:)`; `prepare(width:height:)`; `encode(output:commandBuffer:source:)`.

## Glow settings (app, `AppSettings`)

| Key | Type | Absent | Invalid |
|---|---|---|---|
| `settings.circularSpectrum.glow` | Bool | false | — |
| `settings.circularSpectrum.glowIntensity` | Double | 0.5 | clamped / NaN → 0.5 |
| `settings.circularSpectrum.glowRadius` | Double | 0.02 | clamped / NaN → 0.02 |
| `settings.circularSpectrum.glowThreshold` | Double | 0.7 | clamped / NaN → 0.7 |

`AppSettings.glowParameters` → `BloomParameters`. All four keys join `AppSettings.allKeys` and the
device privacy check's allowed list (`scripts/run_device_tests.py`).

## State: the host's glow

`off` (parameters pass-through: generator draws to the drawable) → `on` (chain with bloom) on any
setting change, from the next frame. `unavailable` (bloom could not be built): stays for the host's
life; frames as `off`.
