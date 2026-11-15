# Research: UIX-010 Batch Parameter Reset

- **UIX-010-D1 One undo step**: Decision: `history.endCoalescing()`, write every value, then `history.recordStep(label:)`. Rationale: `recordStep` records the current inputs once with no coalescing key and closes coalescing; the observation callback that follows finds equal bytes and records nothing (SCN-008-D5). Alternatives: relying on observation (several writes in one run loop turn would also be one capture, but its label would be "Scene", and a later edit could coalesce into it).
- **UIX-010-D2 Write path**: Decision: the plain `ParameterInspectorTargets.target(for:settings:)` (lock-guarded), not `quantizedTarget`. Rationale: MOD-017 could queue discrete values for the next beat, splitting the reset across undo steps (R9).
- **UIX-010-D3 Already at default**: Decision: compare `target.get()` with `descriptor.defaultValue` (`ParameterValue` equality) before writing. Rationale: same rule as SCN-008 recall; no write, no count.
- **UIX-010-D4 Lock**: Decision: `settings.sceneLock.refusesEdit()` before anything; it announces the refusal itself, so the view does not announce it again.
- **UIX-010-D5 Bindings**: Decision: untouched. The reset writes only Settings base values; MOD-012 bindings are separate scene inputs.
- **UIX-010-D6 Host screen**: Decision: the UIX-009 parameter list, because the inspector is a one-parameter sheet and the list already shows every parameter by group with its value.
- **UIX-010-D7 Labels**: "Reset <name>" for one parameter, "Reset <n> Parameters" for several (undo label); announcement "Reset <name>" / "Reset <n> parameters"; button "Reset <n> to Defaults", accessibility label "Reset <n> parameters to defaults" ("1 parameter").
