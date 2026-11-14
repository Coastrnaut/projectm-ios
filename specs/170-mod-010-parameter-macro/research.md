# Research: MOD-010 Parameter Macro

## MOD-010-D1: Evaluation order and exactness

- **Decision**: `position = curve.apply(invert ? 1 − m : m)` with `m` limited to 0…1 (non-finite → 0), then
  `LinearMapping.interpolate(from: minimum, to: maximum, at: position)`, then limited to the registry range.
  Continuous targets use the result; integer targets round to the nearest step from the minimum (ties away
  from zero) and are limited again; enum targets read minimum/maximum as case positions and pick
  `cases[round(result)]`.
- **Rationale**: Reuses MOD-004 (exact 0 at 0 and 1 at 1, monotonic) and MOD-003 (exact ends, bounded), so
  the acceptance's "exactly at the ends" holds by construction. `1 − m` is exact for m = 0 and 1.
- **Alternatives**: applying invert by swapping the range ends (equivalent for linear, but different from the
  roadmap's formula for asymmetric curves; rejected to keep the stated semantics).

## MOD-010-D2: Base value, not a modulation source

- **Decision**: the app writes the evaluated values through UIX-003's `ParameterInspectorTargets` (the
  Settings path). Bindings, LFOs and ACC-012's render clamp apply on top unchanged.
- **Rationale**: predictable; no new per-frame path; the inspector, shelf and Settings show the macro's result.
- **Alternatives**: a modulation source (`AudioFeatureSource.macro`) — needs per-frame plumbing and a mix
  rule with bindings; left to a later row.

## MOD-010-D3: Scene storage

- **Decision**: optional top-level `macros` list of verbatim objects (`name`, `value`, `targets[]` with
  `parameter`, `curve` text form, `minimum`, `maximum`, `invert`); defaults: linear curve, full range, not
  inverted. Read by position; warnings `invalidMacro` (`$.macros[i]`, `$.macros[i].targets[j]` and their keys)
  and `unknownMacroTarget` (`$.macros[i].targets[j].parameter`). The usable targets of a macro stay live. A
  macro change rewrites only its `value` field, so unknown fields survive.
- **Rationale**: the pattern of `effects`, `triggers` and `lfos` (MOD-006/007): no format version change, a
  scene without macros encodes byte-identically, QA-004's matrix gains no row.
- **Alternatives**: macros inside `parameters` (would collide with MOD-001's value map); rejected.

## MOD-010-D4: Undo

- **Decision**: `SceneInputs.macros` holds the macro entries; `SceneHistoryEdit.describe` checks macros first:
  when exactly one macro's value changed the edit is "Macro <name> <percent>" with key `macro.<index>`,
  whatever targets changed with it; the slider's drag end and each accessibility step end coalescing.
- **Rationale**: one drag = one undo step restoring the macro and all its targets (SCN-010 restores the
  whole input state).

## MOD-010-D5: UI scope and MIDI

- **Decision**: Settings › Macros (only when the scene has macros): an ACC-005 slider per macro
  (identifier `macro.<index>`, label = name, 1% steps, spoken as percent) and read-only target rows
  (identifier `macroTarget.<index>.<parameter>`, "<name>: <value>"). No editor; DEBUG `-uitestSeedMacro`
  seeds the acceptance macro. No `macro.<index>` registry ID for MIDI-003 learn (deferred: MIDI-003 maps
  registry descriptors only).
