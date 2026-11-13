# Data Model: MOD-003 Linear Mapping

## LinearMapping (value type; `Sendable`, `Hashable`)

| Field | Type | Default | Rule |
|---|---|---|---|
| `inputMinimum` | Double | 0 | finite, below `inputMaximum` (for `isValid`) |
| `inputMaximum` | Double | 1 | finite |
| `outputStart` | Double | — | finite; the value at position 0 |
| `outputEnd` | Double | — | finite; the value at position 1; below the start inverts |

Derived: `isValid` (all four finite, input minimum below maximum), `isInverted`
(`outputEnd < outputStart`), `isConstant` (`outputEnd == outputStart`).

Operations (contract L1-L5): `position(of:)`, `interpolate(_:)`, `map(_:)`, static
`interpolate(from:to:at:)`, static `clampedPosition(_:)`. No state, no lifecycle.

## AudioFeatureBinding (MOD-002, changed)

Gains `mapping: LinearMapping` (computed from and writing to its four range fields). Validation
(MOD-002 contract C2) is unchanged.

## AudioFeatureModulator (MOD-002, changed)

`advance`: position = `binding.mapping.position(of: feature)`. Effective value: mapped =
`binding.mapping.interpolate(signal)`. Everything else unchanged.
