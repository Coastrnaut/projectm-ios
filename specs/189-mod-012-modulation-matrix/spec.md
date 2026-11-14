# Feature Specification: MOD-012 Modulation Matrix UI

**Feature Branch**: `feature/mod-012` (spec directory `189-mod-012-modulation-matrix`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MOD-012 (Modulation matrix UI) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "List, enable, reorder and inspect every mapping." Acceptance, verbatim:
"Disabling one row affects only its destination route." Priority P1, effort L, depends on MOD-002
(integrated)."

Identifiers in this feature carry the roadmap ID: requirements `MOD-012-R1…`, success criteria
`MOD-012-S1…`, research decisions `MOD-012-D1…`, tasks `MOD-012-T01…`. Other features are cited by their own
IDs: MOD-002 (audio feature bindings), MOD-003 (output range), MOD-004 (curves), MOD-005 (envelopes), MOD-006
(threshold triggers), MOD-007 / MOD-009 (LFOs), MOD-010 (macros), MOD-011 (layers and mix order, ADR-0057),
UIX-003 (parameter inspector), SCN-001 / SCN-002 / SCN-010 / SCN-012 (scene document, autosave, undo, issue
report), ACC-005 / ACC-012 (accessible controls, sensory safety).

## Baseline: what exists today (audit of 2026-11-14, commit `f80ed10c`)

| Question | Today |
|---|---|
| Editor | **None.** Bindings come only from scenes and DEBUG launch paths. MOD-002, MOD-004, MOD-005, MOD-006, MOD-007/009, MOD-010 and MOD-011 each recorded the missing editor. |
| Bindings | `AudioFeatureModulator` (ParameterGraph): up to 32 bindings, up to 4 layers per parameter (MOD-011), folded in list order with a clamp after each step, integer snap at the end, ACC-012 last (`GlowModulationOrder`). API: `bind`, `addLayer`, `unbind` (all layers), `bindings(for:)`, `layerCount(for:)`, `signal(for:layer:)`, `setEnvelope(_:for:layer:)`. |
| Enable flag | None: a binding exists or not. |
| Order | Only the order added; no way to reorder. |
| Where bindings live | The native spectrum host's modulator while a native visual exists; otherwise the scene autosave carry (`SceneAutosaveCarry.bindings`), handed to a host when one is created. |
| Scene storage | `$.bindings` entries (source, target, input, output, mix, envelope, expression, curve), unknown fields kept in `extra`. |
| Undo | SCN-010 records `SceneInputs` changes; bindings are not in `SceneInputs`, so no binding change is undoable. |
| Inspector | UIX-003 lists a parameter's bindings ("Source → range (mix)"), numbered when layered (MOD-011-R8). |
| Triggers, LFOs, macros | Stored in the scene (MOD-006 `triggers`, MOD-007 `lfos`, MOD-010 `macros`); macros have a Settings section (MOD-010), triggers and LFOs none. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: Where does the matrix live and what does it list? → A: Settings → **Modulation** (a row with the route count that opens its own screen). It lists every audio-feature and LFO binding (the MOD-002/MOD-011 bindings), **grouped by destination** (one section per parameter, in the order the parameters first appear in the binding list), **layers in fold order** within each group. Each row shows source → destination, mix mode, range, curve and envelope in one line and has an on/off switch. Threshold triggers (MOD-006) and macros (MOD-010) are shown as **read-only** sections below; LFOs appear as sources ("LFO 1") (MOD-012-R1, R2).
- Q: How is a row disabled without deleting it? → A: A new `isEnabled` flag on the binding (default on). A disabled layer is **skipped** in the MOD-011 fold: the other layers of that parameter fold as if it were absent, and other parameters are untouched. Its signal keeps advancing, so turning it back on resumes without a jump in the envelope. When every layer of a parameter is off, the parameter takes its base value exactly, as if unbound (MOD-012-R3, R4).
- Q: How is the flag stored? → A: As an optional `enabled` boolean on the scene binding, written only when false; absent means enabled. No version bump; older versions keep the unknown field verbatim in `extra` (and apply the binding, which is the conservative reading of an older reader) (MOD-012-R5).
- Q: How does reordering work? → A: Only **within one destination** (the fold order is per parameter; moving a binding to another destination would change what it does). Edit mode with drag handles, and the VoiceOver actions "Move Up" and "Move Down" on each layer row. The new order is the fold order, so the result follows the MOD-011 contract with the new list order. A move across destinations is refused (MOD-012-R6).
- Q: What does inspecting a row show? → A: A detail screen: source, destination, mix mode, input and output ranges, a curve preview (the MOD-004 curve drawn over 0…1), envelope attack and release, and live values refreshed at 10 Hz while open (the layer's signal and mapped value, and the destination's modulated value), with a button that opens the UIX-003 inspector for the destination (MOD-012-R7).
- Q: Create and delete routes? → A: **Not in this feature.** Creating a route needs source, destination, mode, range, curve and envelope pickers with validation messages; that is a separate editor. MOD-012 stops at list, enable, reorder and inspect, as the roadmap row states; bindings still come from scenes (and the DEBUG seed). Recorded as the scope decision MOD-012-D6 (MOD-012-R10).
- Q: How do changes save and undo? → A: Each toggle or move changes the current scene's binding list at once, is saved by SCN-002 autosave, and is **one SCN-010 undo step** ("Turn Off Kick → Glow Intensity", "Turn On …", "Reorder Glow Intensity"). The binding list joins `SceneInputs`; undo and redo set the list back (MOD-012-R8).
- Q: How is it tested without audio? → A: Package tests with injected features and frame times (the acceptance: A kick → glow intensity, B LFO → glow intensity as a second layer, C band → glow radius; disable B; intensity equals the A-only value exactly, radius bit-identical, A's own signal unchanged; re-enable B gives the two-layer fold). A DEBUG seed `-uitestSeedModulationMatrix` gives the scene three constant-range routes so a UI test can read a deterministic per-destination probe (MOD-012-S1 to S6).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Turn one route off without touching the others (Priority: P1)

A performer's scene drives the glow intensity from the kick, adds an LFO layer on the same intensity and
drives the glow radius from a band. In Settings → Modulation they switch the LFO layer off: the glow
intensity now follows the kick alone, and nothing else moves.

**Why this priority**: This is the roadmap row's acceptance.

**Independent Test**: With injected features, compare the destination values before and after the toggle
against the single-layer and two-layer folds, bit for bit.

**Acceptance Scenarios**:

1. **Given** routes A (kick → glow intensity), B (LFO 1 → glow intensity, second layer) and C (band → glow radius), **When** B is turned off, **Then** the intensity equals the value with only A applied, exactly; the radius is bit-identical to before; A's signal is unchanged.
2. **Given** B is off, **When** it is turned on again, **Then** the intensity equals the two-layer fold of A then B.
3. **Given** every layer of a parameter is off, **When** evaluated, **Then** the parameter equals its base value exactly.

### User Story 2 - See every route grouped by destination (Priority: P1)

**Independent Test**: The matrix model built from a binding list groups by destination in first-appearance
order, with layers in fold order, and describes each row.

**Acceptance Scenarios**:

1. **Given** bindings for two parameters, **When** Settings → Modulation opens, **Then** there is one section per parameter, layers numbered in fold order, each with source, mix mode, range, curve, envelope and an on/off switch.
2. **Given** the scene has threshold triggers or macros, **When** the matrix opens, **Then** they are listed read-only.
3. **Given** no binding, **When** the matrix opens, **Then** it says there are no routes and that routes come with scenes.

### User Story 3 - Reorder the layers of one destination (Priority: P2)

**Independent Test**: Moving a layer changes the fold result exactly as the MOD-011 contract predicts for
the new order; a move across destinations is refused.

**Acceptance Scenarios**:

1. **Given** an add layer then a multiply layer on one parameter, **When** the multiply layer is moved first, **Then** the value equals the fold multiply-then-add.
2. **Given** VoiceOver, **When** "Move Up" is chosen on the second layer, **Then** it becomes the first.

### User Story 4 - Inspect one route (Priority: P2)

**Acceptance Scenarios**:

1. **Given** a route, **When** its row is tapped, **Then** a detail screen shows source, ranges, curve preview, envelope times and live values, and a button opens the parameter inspector for the destination.

### User Story 5 - Changes persist and undo (Priority: P2)

**Acceptance Scenarios**:

1. **Given** a route turned off, **When** the scene is saved and reopened, **Then** the route is still off; a stored binding without the flag is on.
2. **Given** a toggle and a move, **When** Undo is chosen twice, **Then** each is undone as its own step and the routes are back as before.

### Edge Cases

- All layers of a parameter off: the base value exactly (as unbound); ACC-012 still applies to the base as before.
- An integer parameter with its only enabled layer off: the base value, not re-snapped.
- A move with a destination index out of range, or across destinations: refused, nothing changes.
- A toggle on a row whose binding no longer exists (the scene changed meanwhile): ignored.
- Undo to a state with a different list: the list is replaced; signals of replaced layers restart at 0 (one envelope step).
- An older app version reading a scene with `enabled: false`: the field is kept verbatim and that version applies the binding.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-012-R1**: Settings MUST offer a Modulation screen listing every audio-feature and LFO binding of the current scene, grouped by destination in first-appearance order, layers in fold order.
- **MOD-012-R2**: Each row MUST show source → destination, mix mode, output range, curve, envelope and its on/off state; threshold triggers and macros MUST be listed read-only.
- **MOD-012-R3**: A binding MUST carry an enabled flag (default on); a disabled layer MUST be skipped in the MOD-011 fold, leaving every other layer and every other parameter bit-identical.
- **MOD-012-R4**: With every layer of a parameter off, its value MUST be its base value exactly; a disabled layer's signal MUST keep advancing.
- **MOD-012-R5**: Scenes MUST store the flag as an optional `enabled` field written only when false; absent MUST mean enabled; no format version change.
- **MOD-012-R6**: Layers MUST be reorderable within one destination (Edit mode drag and VoiceOver Move Up/Move Down); the new order MUST be the fold order; moves across destinations MUST be refused.
- **MOD-012-R7**: Tapping a row MUST show its details (source, ranges, curve preview, envelope times, live values at ≤ 10 Hz while open) and a way to open the UIX-003 inspector for the destination.
- **MOD-012-R8**: Each toggle and move MUST change the current scene at once (SCN-002 autosave) and be one SCN-010 undo step with a descriptive name.
- **MOD-012-R9**: Toggling and moving MUST keep per-frame evaluation allocation-free and deterministic.
- **MOD-012-R10**: Creating and deleting routes is out of scope; the screen MUST say routes come with scenes.

### Key Entities

- **Route**: one binding (source, destination, mix, range, curve, envelope, enabled) at a layer position of its destination.
- **Destination group**: a parameter's routes in fold order.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-012-S1**: In the acceptance setup (A, B, C), disabling B gives intensity == the A-only fold exactly, radius bit-identical to before, A's signal bit-identical; re-enabling B gives the two-layer fold exactly.
- **MOD-012-S2**: Reordering two layers of one destination changes the result to the fold in the new order (exact), and a cross-destination move is refused.
- **MOD-012-S3**: `enabled: false` round-trips through a scene document; a binding without the field restores enabled.
- **MOD-012-S4**: A toggle and a move are two undo steps; undoing both restores the original list.
- **MOD-012-S5**: A UI test under 30 s opens Modulation with a seeded scene, turns one row off, and the probe value changes for that destination only.
- **MOD-012-S6**: The changed packages build and pass on Linux (CI shape).

## Assumptions

- Bindings still come from scenes; the matrix edits the enable flag and the order only.
- LFOs are binding sources (`audio.lfo.<n>`, MOD-007), so LFO routes are rows like any other.
- The undo history is in memory only (SCN-010); a replaced list restarts the replaced layers' signals.
