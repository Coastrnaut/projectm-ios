# Data Model: SHOW-004 Cue Transition Override

## ShowCue (ShowControl) — changed

| Field | Type | Rule |
|---|---|---|
| `transition` | `ShowCueTransition?` | SCN-007 scene default; unchanged by SHOW-004 |
| `transitionOverride` | `ShowCueTransition?` | **new**; nil = use the scene default |
| `effectiveTransition` | computed | `transitionOverride ?? transition` |

`ShowCueList.setTransitionOverride(_:to:)` sets or (nil) removes it; never changes the position, order or
`transition`. `insert(…, transitionOverride:)` carries it for Duplicate Scene.

## show.json cue entry (version 1, unchanged version)

```json
{ "id": "…", "label": "…", "scene": "…",
  "transition": { "duration": 2, "easing": "linear", "type": "crossfade" },
  "transitionOverride": { "duration": 0, "easing": "linear", "type": "cut" } }
```

Absent or null = no override. See [contracts/show-cue-transition-override.md](contracts/show-cue-transition-override.md).

## ShowDecodeWarning — new cases

- `droppedTransitionOverrides(Int)`: invalid overrides left out.
- `unknownTransitionOverrideType(cue: String, type: String)`: kept, applied as a cut.
