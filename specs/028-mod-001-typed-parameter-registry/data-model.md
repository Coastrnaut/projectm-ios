# Data Model: MOD-001 Typed Parameter Registry

All types are `Sendable`; value types are `Equatable`/`Hashable` where noted. Module:
`ParameterGraph` unless stated.

## ParameterID (`Hashable`, `Comparable`, `Codable` as a single string)

| Field | Type | Rule |
|---|---|---|
| rawValue | String | ≥ 2 segments split by `.`; each `[a-z][A-Za-z0-9]*`; ≤ 128 characters (MOD-001-R1) |

`ParameterID("visual.circularSpectrum.gap")` never fails; `isWellFormed` and `syntaxProblem`
report the defect so validation (not construction) rejects it. Segments: `domain` (first),
`segments`.

## ParameterGroup (`Hashable`)

| Field | Type | Rule |
|---|---|---|
| id | String | ≥ 1 segment, same segment syntax as IDs |
| displayName | String | non-empty; one group ID has one display name across the catalog |

## ParameterUnit (`String` raw values, stable)

`none`, `normalized`, `fractionOfOutput`, `seconds`, `perSecond`, `degrees`, `count`.

## ParameterCurve (`String` raw values)

`linear` (default), `logarithmic` (requires min > 0), `exponential`. A hint for UI and MOD-004;
never applied by the store.

## ParameterKind

| Case | Payload | Validation |
|---|---|---|
| continuous | range: ClosedRange<Double>, default: Double, step: Double?, curve | bounds finite, min < max, step finite > 0 if present, default finite in range, log curve needs min > 0 |
| integer | range: ClosedRange<Int>, default: Int, step: Int | min < max, step ≥ 1, default in range |
| boolean | default: Bool | — |
| enumeration | cases: [ParameterEnumCase], default: String | ≥ 1 case, case IDs well formed (`[a-z0-9][A-Za-z0-9]*`) and unique, display names non-empty, default is a case ID |
| color | default: ParameterColor | components finite in 0…1 |

`ParameterEnumCase { id: String; displayName: String }`.
`ParameterColor { red, green, blue, alpha: Double }` (linear, straight alpha).

## ParameterValue (`Hashable`, `Codable`)

`continuous(Double)`, `integer(Int)`, `boolean(Bool)`, `enumeration(String)`, `color(ParameterColor)`.
JSON: `{"kind":"continuous","value":0.5}`, `{"kind":"color","value":[r,g,b,a]}`.

## ModulationMixMode (`String` raw values)

`replace`, `add`, `multiply` (MOD-011 defines order and clamping).

## ModulationPolicy (`Hashable`)

| Field | Type | Rule |
|---|---|---|
| isModulatable | Bool | |
| mixModes | [ModulationMixMode] | empty iff not modulatable; no duplicates; add/multiply only for continuous and integer |
| allowsExternalControl | Bool | MIDI/OSC may set the manual value |

Presets: `.continuousDefault` (modulatable, [replace, add, multiply], external),
`.discreteManual` (not modulatable, [], external), `.none` (not modulatable, no external control).

## ParameterDescriptor

| Field | Type |
|---|---|
| id | ParameterID |
| displayName | String (non-empty) |
| group | ParameterGroup |
| unit | ParameterUnit |
| kind | ParameterKind |
| modulation | ModulationPolicy |
| registrationSite | `ParameterRegistrationSite { fileID: String; line: Int }` (captured by default arguments) |

Derived: `defaultValue: ParameterValue`.

## ParameterRegistry (immutable value)

| Member | Meaning |
|---|---|
| `init(descriptors:retiredIDs:) throws(ParameterRegistryError)` | validates (MOD-001-R5) |
| `static func validate(_:retiredIDs:) -> [ParameterValidationIssue]` | issues without throwing |
| `descriptors` | registration order (MOD-001-R6) |
| `ids`, `groups` | in first-appearance order |
| `descriptor(for:)` | O(1) lookup |
| `descriptors(inGroup:)` | registration order |

`ParameterValidationIssue { parameter: ParameterID?; problem: Problem; message: String }` with
`Problem` cases: `duplicateID`, `malformedID`, `retiredID`, `emptyDisplayName`, `malformedGroup`,
`conflictingGroupName`, `nonFiniteNumber`, `emptyRange`, `invalidStep`, `defaultOutOfRange`,
`invalidCurve`, `noEnumCases`, `malformedEnumCase`, `duplicateEnumCase`, `unknownEnumDefault`,
`colorOutOfRange`, `invalidModulationPolicy`. `ParameterRegistryError.description` joins every
message, one per line.

## ParameterStore (`final class`, `Sendable`)

State (under a `Mutex`): `values: [ParameterID: ParameterValue]`, `changeCount: UInt64`,
`observers: [UInt64: @Sendable (ParameterChange) -> Void]`.

| Member | Meaning |
|---|---|
| `init(registry:)` | every value = its default, `changeCount` 0 |
| `value(for:) -> ParameterValue?` | |
| `double(_:)`, `int(_:)`, `bool(_:)`, `enumCase(_:)`, `color(_:)` | typed reads; nil for unknown ID or other kind |
| `set(_:for:) throws(ParameterStoreError) -> ParameterValue` | clamps; returns stored value |
| `setDouble/ setInt/ setBool/ setEnumCase/ setColor` | typed convenience |
| `reset(_:)`, `resetAll()` | back to defaults (each effective change notifies) |
| `observe(_:) -> ParameterObservation` | token; `cancel()` |
| `changeCount` | monotonic |
| `snapshot()`, `restore(_:) -> ParameterRestoreReport` | MOD-001-R9 |

`ParameterChange { id; oldValue; newValue; changeCount }`.
`ParameterStoreError`: `unknownParameter(id)`, `kindMismatch(id, expected, got)`,
`nonFiniteValue(id)`, `unknownEnumCase(id, caseID)`; readable `description`.

## ParameterSnapshot (`Codable`, `Equatable`)

`schemaVersion: Int` (current 1), `values: [ParameterID: ParameterValue]` (encoded as a JSON object
keyed by ID, sorted keys). `ParameterRestoreReport { applied: [ParameterID]; orphaned:
[ParameterID]; rejected: [(ParameterID, ParameterStoreError)] }`, sorted by ID; a snapshot with
`schemaVersion` above the current one is rejected as a whole (`unsupportedVersion`).

## VisualParameterCatalog (module `VisualParameters`)

| ID | Kind | Range / cases | Default | Unit | Policy | Source |
|---|---|---|---|---|---|---|
| `visual.circularSpectrum.barCount` | enum | 16, 32, 64, 128 | 64 | count | discreteManual | `SpectrumBarCount.allCases`, `CircularSpectrumConfiguration().barCount` |
| `visual.circularSpectrum.innerRadius` | continuous | 0.05…0.9 | 0.3 | fractionOfOutput | continuousDefault | `innerRadiusRange`, default instance |
| `visual.circularSpectrum.gap` | continuous | 0…0.9 | 0.2 | normalized | continuousDefault | `gapRange`, default instance |
| `visual.linearSpectrum.barCount` | enum | 16, 32, 64, 128 | 64 | count | discreteManual | `LinearSpectrumConfiguration().barCount` |
| `visual.linearSpectrum.orientation` | enum | vertical, horizontal | vertical | none | discreteManual | `LinearSpectrumOrientation.allCases` |
| `visual.linearSpectrum.spacing` | continuous | 0…0.9 | 0.2 | normalized | continuousDefault | `spacingRange`, `defaultSpacing` |
| `visual.linearSpectrum.capThickness` | continuous | 0…0.05 | 0.015 | fractionOfOutput | continuousDefault | `capThicknessRange`, `defaultCapThickness` |
| `visual.linearSpectrum.peakHold` | continuous | 0…5 | 0.5 | seconds | continuousDefault | `peakHoldRange`, `defaultPeakHoldSeconds` |
| `visual.linearSpectrum.peakFall` | continuous | 0.1…10 | 1.0 | perSecond | continuousDefault | `peakFallRange`, `defaultPeakFallPerSecond` |
| `effect.bloom.enabled` | boolean | — | false | none | discreteManual | `BloomParameters().enabled` |
| `effect.bloom.intensity` | continuous | 0…1 | 0.5 | normalized | continuousDefault | `intensityRange`, `defaultIntensity` |
| `effect.bloom.radius` | continuous | 0.005…0.06 | 0.02 | fractionOfOutput | continuousDefault | `radiusRange`, `defaultRadius` |
| `effect.bloom.threshold` | continuous | 0.1…1 | 0.7 | normalized | continuousDefault | `thresholdRange`, `defaultThreshold` |
| `effect.bloom.knee` | continuous | 0…1 | 0.5 | normalized | continuousDefault | `kneeRange`, `defaultKnee` |

Bloom values are `Double(Float)` conversions of the `Float` constants (for example 0.02 →
0.0199999995529651). Retired IDs: none.
