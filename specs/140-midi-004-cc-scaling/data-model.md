# Data Model: MIDI-004 MIDI CC Scaling

## Mapping options (`MIDIMappingOptions`)

| Field | Type | Default | Rule |
|---|---|---|---|
| curve | MOD-004 `MappingCurve` | `.linear` | Always valid when used; an unreadable stored curve reads `.linear` |
| inverted | Bool | false | `invert=1` |
| unreadableCurveText | String? | nil | The stored text after `curve=` when it did not parse or was invalid; written back unchanged; cleared when a curve is chosen |
| extraSegments | [String] | [] | Unknown `;` segments, verbatim, in order |

Derived: `position(normalized:)` (clamp to 0…1, non-finite → 0; invert; curve), `preset`
(`MIDICurvePreset?`, nil = Custom), `summary` ("Linear", "Ease in, inverted", "Custom", "Linear (curve not
readable)"), `isDefault`.

## Curve preset (`MIDICurvePreset`)

`linear`, `easeIn` (`easeIn(2)`), `easeOut` (`easeOut(2)`), `logarithmic` (`logarithmic(9)`); `title`,
`curve`.

## Binding (`MIDIControlBinding`, extended)

MIDI-003 key and target plus `options`. Storage line: MIDI-003 line + option segments (research D2).

## Binding list (`MIDIBindingList`, extended)

Unchanged policy (one per control and per parameter, 64 max). `bind` carries the target's options
(research D5); `setOptions(_:for:)` replaces a mapped target's options (false when unmapped);
`binding(forKey:)`.

## Value

`value = LinearMapping.interpolate(from: minimum, to: maximum, at: options.position(normalized: v / 127))`
for a continuous descriptor; nil otherwise.
