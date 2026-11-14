# Data Model: SCN-007

## ShowTransitionType (ShowControl)
`cut` | `crossfade` | `dipToBlack` | `unknown(String)`. Text form = the CMP-014 style raw values; an unknown type keeps its text (1…64 characters).

## ShowCueTransition (ShowControl)
| Field | Type | Rule |
|---|---|---|
| type | ShowTransitionType | as above |
| durationSeconds | Double | finite, 0…10 |
| easing | MappingCurve | `isValid`; default `.linear` |

`ShowCue.transition: ShowCueTransition?` (nil = default: a cut).

## SceneTransitionSpec (Compositor, extended)
Adds `curve: MappingCurve?` (nil = `easing`). Invalid curve → `SceneTransitionError.invalidCurve`.

## Warnings (ShowDecodeWarning)
- `unknownTransitionType(cue: String, type: String)`
- `droppedTransitions(Int)`
