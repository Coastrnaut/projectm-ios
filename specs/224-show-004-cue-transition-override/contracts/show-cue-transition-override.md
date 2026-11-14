# Contract: cue transition override in `show.json` and in the step path

- **O1 (write)**: A cue with an override writes `transitionOverride` as an object with exactly `duration` (number), `easing` (MOD-004 text form) and `type` (string); a cue without one writes no key. Keys are sorted; a show without overrides is byte-identical to the output before SHOW-004.
- **O2 (read, lenient)**: Absent or null → no override. Not an object, a missing field, a duration outside 0…10 s or not finite, an unreadable or invalid easing, an empty or over-64-character type → the override is dropped, counted in `droppedTransitionOverrides(n)`, and the show loads. An unknown type → kept verbatim with `unknownTransitionOverrideType(cue:type:)`.
- **O3 (round trip)**: decode → encode of a written file is byte-identical; durations are bit-identical.
- **O4 (apply)**: Every step that makes a cue active drives `CueTransitionResolver.resolved(cue.transitionOverride ?? cue.transition, …)` just before the scene is applied. An unknown type resolves to a cut.
- **O5 (isolation)**: No override operation (set, remove, step, duplicate) writes a scene file or changes any cue's `transition`.
- **O6 (edit)**: `ShowCoordinator.setTransitionOverride` is refused while the scene is locked (SCN-015), otherwise saves at once and applies nothing.
