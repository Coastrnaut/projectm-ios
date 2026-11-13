# Data Model: MOD-002 Audio Feature Binding

All types are in `Packages/ParameterGraph` unless noted. Nothing is persisted in this row.

## AudioFeatureSource (enum, `Sendable`, `Hashable`)

| Case | ID | Value read from a frame |
|---|---|---|
| `band(Int)` | `audio.band.<index>` | `bands[index]` if `index < bands.count`, else 0 |
| `bandMean` | `audio.bandMean` | mean of `bands` (0 when empty) |
| `onset` | `audio.onset` | the frame's onset value, else 0 |
| `beatConfidence` | `audio.beatConfidence` | the frame's beat confidence, else 0 |

- `maximumBandIndex = 127`. Non-finite readings are 0 (MOD-002-R6). `id` and `init?(id:)` round-trip.

## AudioFeatureFrame (struct, non-escaping use)

- `bands: UnsafeBufferPointer<Float>` (borrowed for the `advance` call), `onset: Float?`,
  `beatConfidence: Double?`. `AudioFeatureFrame.silent` has no bands and no values.

## AudioFeatureEnvelope (struct, `Sendable`, `Hashable`)

- `attackSeconds: Double`, `releaseSeconds: Double`; `.none` = (0, 0). Valid: finite, 0…60.

## AudioFeatureBinding (struct, `Sendable`, `Hashable`)

| Field | Type | Rule |
|---|---|---|
| `source` | `AudioFeatureSource` | band index 0…127 |
| `target` | `ParameterID` | registered, continuous or integer, modulatable |
| `inputMinimum`, `inputMaximum` | `Double` | finite, minimum < maximum |
| `outputStart`, `outputEnd` | `Double` | finite; replace: in target range; add: in ±span; multiply: in 0…1 |
| `mixMode` | `ModulationMixMode` | allowed by the target's policy |
| `envelope` | `AudioFeatureEnvelope` | as above |

## AudioFeatureBindingError (enum, `Error`, readable `description`)

`unknownTarget(id)`, `notNumeric(id, kind)`, `notModulatable(id)`, `mixModeNotAllowed(id, mode)`,
`bandIndexOutOfRange(id, index)`, `invalidInputRange(id)`, `outputOutOfRange(id, mode, allowed)`,
`invalidEnvelope(id)`, `tooManyBindings(limit)`. Every message names the target.

## AudioFeatureModulator (final class, one owner)

- State: `registry`; `slots` (array reserved for `maximumBindings = 32`): binding, target bounds and
  kind, signal `s`, `lastTime: UInt64?`.
- Lifecycle per slot: `bind` (validated; replaces a slot with the same target, signal 0, no time) →
  `advance` (per frame) → `unbind` (slot removed; effective = manual).
- Reads: `isBound(id)`, `bindings`, `hasBindings`, `signal(for:)`, `value(for:manual: Double)`,
  `value(for:manual: ParameterValue)`, `value(for:in: ParameterStore)`.

## App (Apps/projectM-iOS)

- `NativeSpectrumHost`: `modulator`, `effectiveGlow: BloomParameters`, `glowLuminance:
  ModulatedGlowLuminance`; `bind(_:)`, `unbind(_:)`, `glowModulationReadout`.
- `ModulatedGlowLuminance` (final class, `FrameLuminanceTransfer`, `@unchecked Sendable`, mutated on
  the main thread only): `model: BloomLuminanceModel`.
