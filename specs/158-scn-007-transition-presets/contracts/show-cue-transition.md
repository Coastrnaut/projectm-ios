# Contract: cue transition in show.json (SCN-007)

**X1 Encoding.** A cue entry gains an optional key `transition`:
```json
{"id": "…", "label": "Build", "scene": "…",
 "transition": {"duration": 1.5, "easing": "easeOut:2.0", "type": "crossfade"}}
```
Written only when the cue has a transition. Keys sorted. `easing` is `MappingCurve.textForm`.

**X2 Decoding.** Missing or `null` → no transition. Not an object, a missing/invalid field, a
duration that is not finite or outside 0…10, an easing whose text does not parse or is invalid, or a
type outside 1…64 characters → dropped, counted in `droppedTransitions(n)`. A type other than `cut`,
`crossfade`, `dipToBlack` → kept verbatim, `unknownTransitionType(cue, type)`.

**X3 Round trip.** decode → encode of any file this version wrote is byte-identical; a file without
`transition` keys keeps its bytes.

**X4 Apply.** `CueTransitionResolver.spec(for:)`: nil or unknown → `SceneTransitionSpec.cut`; else
style = type, `durationSeconds` = duration, `curve` = easing (nil when linear, with easing `.linear`).
`resolved(_:reduceMotion:reduceFlashing:)`: Reduce Motion → cut; else Reduce flashing and
(instant or < 0.5 s) → 0.5 s (cut → linear crossfade).

**X5 Driver.** On every cue apply that reaches `applyScene`, the coordinator calls
`transitionDriver.driveTransition(spec, toScene:)` first.
