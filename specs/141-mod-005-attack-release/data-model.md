# Data Model: MOD-005 Attack/Release Envelope

## AudioFeatureEnvelope (existing, ParameterGraph)

| Field | Type | Rule |
|---|---|---|
| `attackSeconds` | Double | Time constant τ for rises; finite, 0…60; 0 = instant |
| `releaseSeconds` | Double | Time constant τ for falls; finite, 0…60; 0 = instant |

New (no stored state): `step(from:toward:elapsedSeconds:) -> Double` (contract E1-E6),
`static func riseTime10To90(timeConstant:)`, `static func timeConstant(riseTime10To90:)`,
`static let tenToNinetyFactor = log(9)`.

## Binding signal (existing, modulator slot)

| Field | Rule |
|---|---|
| `signal` | 0…1, starts at 0 on bind; updated by `step` each advance |
| `lastTime` | nanoseconds of the latest increasing advance; nil until the first |

Transitions: `bind` (new slot, signal 0) → `advance` (step) → `setEnvelope` (times replaced, signal
and lastTime kept) → `unbind` (slot removed).

## Scene binding (existing, SceneFormat)

`"envelope": {"attack": <seconds>, "release": <seconds>}`: optional object, each field optional
(missing = 0); written only as today. Invalid values: binding rejected and kept, issue
`invalidBinding` at `$.bindings[i].envelope`.
