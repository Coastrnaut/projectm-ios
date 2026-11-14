# Feature Specification: MOD-011 Modulation Mix Modes

**Feature Branch**: `feature/mod-011` (spec directory `178-mod-011-mix-modes`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (MOD-011-T01-T10 verified on the Mac: ParameterGraph, VisualGenerators and SceneFormat package tests on the host, app unit tests on a private iOS 27.2 simulator; ADR-0057; no device task)

**Input**: User description: "Implement MOD-011 (Modulation mix modes) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Combine manual, audio and LFO sources via replace, add and multiply."
Acceptance, verbatim: "Order and clamping are documented and unit-tested." Priority P1, effort M, depends
on MOD-002 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `MOD-011-R1…`, success criteria
`MOD-011-S1…`, research decisions `MOD-011-D1…`, tasks `MOD-011-T01…`. Other features are cited by their
own IDs: MOD-001 (typed parameter registry and its modulation policy), MOD-002 (audio feature bindings and
their mix mode), MOD-003 (output range), MOD-004 (curve), MOD-005 (envelope), MOD-007 / MOD-009 (LFOs as
`audio.lfo.<n>` sources), MOD-010 (macros write the manual value), MOD-013 (binding serialization),
MOD-014 (modulation graph), MIDI-003 (MIDI live values), ACC-012 (sensory safety clamp), UIX-003
(parameter inspector), SCN-001 / SCN-002 / SCN-012 (scene document, autosave, issue report).

## Baseline: what exists today (audit of 2026-11-14, commit `3b2d21b8`)

| Question | Today |
|---|---|
| Mix modes | MOD-002 `ModulationMixMode` replace, add, multiply. `AudioFeatureModulator.effective`: mapped = range(curve(envelope(source))); replace → mapped; add → manual + mapped (output range within ± the parameter's span); multiply → manual × mapped (output range within 0…1). A non-finite result falls back to the manual value; then clamp to the registry range; integers round half away from zero and snap to the step. No depth parameter. |
| Sources | Audio features and, since MOD-007, the scene's LFOs (`audio.lfo.<n>`) are the same kind of binding source. |
| Several bindings on one parameter | **Not possible.** `bind` replaces the target's binding (one per parameter); SCN-001 restore rejects a second binding on a bound target (`duplicateBindingTarget`, kept verbatim). So audio and an LFO cannot be combined on one parameter. |
| Base value | The manual value: Settings, the inspector, the shelf, MOD-010 macros, snapshot recall and undo all write it. A MIDI-003 live value, while one exists for the parameter, replaces it before modulation (`BloomParameters.applying`). |
| Safety | ACC-012 after modulation: the excursion from the base is scaled by the profile's intensity limit (`SafetyClamp.modulated`), then the glow intensity is capped (`BloomParameters.limited(by:)`). |
| Inspector | UIX-003 lists each binding as "Source → range (mix)" in binding order, then "MIDI control". |
| Order documented | Only in code comments of one function; no test of a multi-step order. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: Can several sources act on one parameter, and in which order? → A: Yes. A parameter may have up to **4 bindings** (still 32 in all). They apply in **binding list order**: the order they were added, which is the scene document's `$.bindings` order. MOD-002's `bind` keeps its meaning (it replaces every binding of that parameter with one, in the first one's place); a new "add another binding" operation appends a layer at the end of the list. Removing a parameter's binding removes all its layers (MOD-011-R1, R2).
- Q: Which formulas do the mix modes use? → A: MOD-002's, unchanged, folded over the list with a running value r that starts at the base: replace r ← m; add r ← r + m; multiply r ← r × m, where m is that binding's mapped value (source → envelope → curve → output range). No depth parameter is added: the output range already sets how far a binding moves the value (a "depth" form would change single-binding behaviour). A non-finite step result leaves r unchanged (MOD-011-R3).
- Q: Where is the value clamped? → A: To the parameter's registry range **after every step**, so each later step sees a valid parameter value (add then multiply saturates instead of overflowing, and the result never depends on an out-of-range intermediate). Integer parameters are rounded and snapped to their step **once, at the end**. For one binding this is exactly MOD-002 (MOD-011-R4).
- Q: What is the base value when MIDI and the manual value both exist? → A: Today's behaviour, kept: the MIDI-003 live value while one exists (it is memory only and ends when the mapping is removed); otherwise the manual value, which Settings, MOD-010 macros, snapshot recall and undo all write. Modulation never writes the base (MOD-011-R5).
- Q: Where does the ACC-012 clamp sit? → A: Last, after every binding: the total excursion from the base is scaled by the profile's intensity limit, then the target's own intensity cap applies. At the Standard profile both are identity (MOD-011-R6).
- Q: How do scenes store several bindings on one parameter? → A: As today, one `$.bindings` entry each, in order; restore now accepts up to 4 per parameter. A fifth is rejected with `duplicateBindingTarget` (kept verbatim, as before). A SHD-009 expression belongs to a parameter's first binding; a later binding of that parameter that carries one is rejected with `duplicateBindingTarget`, and capture writes the expression on the first binding only. No version bump: older documents never had applied duplicates (MOD-011-R7).
- Q: How much UI? → A: No editor (bindings still come from scenes and the DEBUG test path). The UIX-003 inspector numbers a parameter's bindings in application order when there is more than one ("1. Average level → … (replace)") and adds one line naming the order when any binding is shown (MOD-011-R8).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Audio and an LFO combine on one parameter in a documented order (Priority: P1)

A performer's scene binds the glow intensity to the average level (replace), adds a slow LFO on top (add)
and scales the result by the onset (multiply). The glow follows all three, and the result is the one the
documented order predicts.

**Why this priority**: This is the roadmap row and its acceptance.

**Independent Test**: A table of manual values, binding lists (both list orders) and source values with
the exact expected effective value at each step, including steps that hit the registry bounds.

**Acceptance Scenarios**:

1. **Given** glow intensity bound to audio (replace, 0.2…0.8), an LFO (add, 0…0.3) and audio (multiply, 0.5…1), **When** the sources are at known values, **Then** the effective value equals the fold replace → add → multiply with a clamp after each step.
2. **Given** the same three bindings in a different list order, **When** evaluated, **Then** the result follows that order and differs where the formulas do not commute.
3. **Given** an add step that would exceed the parameter's maximum, **When** a later multiply applies, **Then** it multiplies the clamped maximum, not the overflow.
4. **Given** a Strict sensory safety profile, **When** the bindings combine, **Then** the ACC-012 excursion scaling and cap apply after every binding.

### User Story 2 - Existing single bindings are unchanged (Priority: P1)

Every scene made before this feature renders exactly as before.

**Independent Test**: Over a grid of manual values, signals, mix modes, curves and output ranges, one
binding's value is bit-identical to the MOD-002 formula.

**Acceptance Scenarios**:

1. **Given** one binding of any mix mode, **When** evaluated over the grid, **Then** every value is bit-identical to MOD-002's.

### User Story 3 - Several bindings survive a scene round trip and show in the inspector (Priority: P2)

**Independent Test**: A scene with two bindings on the glow intensity restores both, in order, and saves
them back unchanged; the inspector lists them numbered.

**Acceptance Scenarios**:

1. **Given** a scene with two bindings on the glow intensity, **When** it is opened, **Then** both apply in document order and the app's glow follows the documented combination.
2. **Given** five bindings on one parameter, **When** restored, **Then** the fifth is rejected with `duplicateBindingTarget` and kept verbatim.

### Edge Cases

- A step yields a non-finite value (cannot happen with valid ranges; guarded): the running value is kept.
- Integer parameters: intermediate values are clamped but not rounded; only the final value is rounded.
- Unbinding a parameter with several layers removes all of them; the parameter returns to its base at once.
- Replace after add discards the add (replace ignores the running value), by definition of the order.
- An expression on a later layer is rejected, not silently dropped.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-011-R1**: A parameter MUST accept up to 4 bindings (32 in all); adding beyond the per-parameter limit MUST be refused with a reason, leaving the bindings unchanged.
- **MOD-011-R2**: A parameter's bindings MUST apply in binding list order (the order added; the scene's document order). Replacing a parameter's binding MUST keep MOD-002's meaning (one binding, in the first one's place); removing it MUST remove all its layers.
- **MOD-011-R3**: Each binding's mapped value MUST be source → envelope → curve → output range, and its mix MUST combine with the running value as replace r ← m, add r ← r + m, multiply r ← r × m, starting from the base; a non-finite step result MUST leave r unchanged.
- **MOD-011-R4**: The running value MUST be clamped to the registry range after every step; integer parameters MUST be rounded (half away from zero) and snapped to their step once at the end. One binding MUST give bit-identical results to MOD-002.
- **MOD-011-R5**: The base MUST be the MIDI-003 live value while one exists, else the manual value; modulation MUST never write the base.
- **MOD-011-R6**: The ACC-012 clamp MUST apply after all bindings: excursion scaling from the base, then the target's cap.
- **MOD-011-R7**: Scene restore MUST apply up to 4 bindings per parameter in document order, reject a fifth and any expression on a later layer with `duplicateBindingTarget` (kept verbatim), and capture MUST write a parameter's expression on its first binding only.
- **MOD-011-R8**: The inspector MUST number a parameter's bindings in application order when it has more than one and state the order in one line.
- **MOD-011-R9**: The order and formulas MUST be documented in an ADR and in the code that evaluates them; evaluation MUST stay deterministic and allocation-free per frame.

### Key Entities

- **Binding layer**: one binding of a parameter, at a position in the binding list.
- **Mix order**: base → layers in list order (clamped after each) → integer rounding → ACC-012.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-011-S1**: The acceptance table (manual + audio replace + LFO add + audio multiply, in at least two list orders, with bound-hitting steps) matches the documented values to 1e-12.
- **MOD-011-S2**: One binding over a grid of at least 500 cases is bit-identical to the MOD-002 formula.
- **MOD-011-S3**: The same inputs evaluated twice in fresh instances give bit-identical results.
- **MOD-011-S4**: In the app, two bindings on the glow intensity give the documented effective glow, and with a Strict profile ACC-012 applies last.
- **MOD-011-S5**: A scene with two bindings on one parameter round-trips both in order; five gives one rejection.
- **MOD-011-S6**: The changed packages build and pass on Linux (CI shape).

## Assumptions

- No binding editor exists; bindings come from scenes and the DEBUG test path.
- Depth is expressed by each binding's output range (MOD-003); no separate depth control is added.
- The per-parameter limit of 4 is enough for manual + audio + LFO combinations and keeps per-frame cost bounded (≤ 32 slots scanned, as today).
