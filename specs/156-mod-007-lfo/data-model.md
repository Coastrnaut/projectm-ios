# Data Model: MOD-007 LFO Sine and Triangle

## LFOShape

`sine` | `triangle` (raw values are the stored names).

## LFO (value type)

| Field | Type | Valid | Default |
|---|---|---|---|
| shape | LFOShape | — | — |
| rateHz | Double | finite, 0.01…20 | — |
| phaseOffset | Double | finite, 0…1 (cycles) | 0 |
| amplitude | Double | finite, 0…1 (peak-to-peak) | 1 |
| center | Double | finite, 0…1 | 0.5 |

- `phase(elapsedNanoseconds:rateHz:)` → 0…<1 (research MOD-007-D2).
- `value(elapsedNanoseconds:maximumRateHz:)` → clamp(center + amplitude/2 · w(φ), 0, 1), with the
  effective rate min(rateHz, maximumRateHz).
- No state: a pure function.

## LFOBank (reference type, one owner)

- `oscillators: [LFO?]` (≤ 8; nil keeps an unusable scene entry's position), `origin: UInt64?`.
- `set(_:)` validates all (throws `LFOError`, unchanged on error) and clears the origin.
- `values(atNanoseconds:maximumRateHz:into:)` sets the origin on first use, writes one value per slot
  (0 for nil) into a caller buffer; allocation-free.

## Binding source

`AudioFeatureSource.lfo(index)`, ID `audio.lfo.<index>`, index 0…7; reads `AudioFeatureFrame.lfos`.

## SceneLFOEntry (SceneFormat)

`fields: [String: SceneJSON]` verbatim. Keys: `shape` (string, required), `rate` (number, required),
`phase`, `amplitude`, `center` (numbers, optional). `read` → `(oscillators: [LFO?], issues)`.
