# Feature Specification: MOD-010 Parameter Macro

**Feature Branch**: `feature/mod-010` (spec directory `170-mod-010-parameter-macro`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MOD-010 (Parameter macro) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Control multiple destinations with one normalized macro value." Acceptance,
verbatim: "Macro changes all targets with their saved mapping curves." Priority P1, effort M, depends on
MOD-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `MOD-010-R1…`, success criteria
`MOD-010-S1…`, research decisions `MOD-010-D1…`, tasks `MOD-010-T01…`. Other features are cited by their
own IDs: MOD-001 (typed parameter registry), MOD-002 (audio bindings), MOD-003 (linear mapping into a
range), MOD-004 (mapping curves with a text form), UIX-003 (parameter inspector and its write path),
UIX-004 (parameter shelf), ACC-005 (accessible sliders), ACC-012 / FR-072 (sensory safety clamps),
SCN-001 / SCN-002 / SCN-010 / SCN-012 (scene document, autosave, undo, issue report), QA-004 (scene
migration matrix meta-test), MIDI-003 (MIDI learn).

## Baseline: what exists today (audit of 2026-11-14, commit `8c7cdac0`)

| Question | Today |
|---|---|
| Registry | MOD-001: every visual parameter has an ID, kind (continuous, integer, boolean, enum, color) and range. |
| Shaping | MOD-004 curves (linear, easeIn/Out/InOut, logarithmic, exponential, piecewise) map 0…1 to 0…1 monotonically, exactly 0 at 0 and 1 at 1, with a text form (`easeIn:2.0`, `log:9.0`). MOD-003 interpolates a position into a range with exact ends. |
| App write path | UIX-003 `ParameterInspectorTargets`: get/set over the Settings property of seven registry parameters (glow on, intensity, radius, threshold; circular bars; linear orientation, spacing). UIX-004's shelf and the inspector both write through it. |
| Undo | SCN-010 records changes of the app's scene inputs; slider drags coalesce by key until a boundary. |
| Safety | ACC-012 clamps the rendered glow (Reduce flashing) after the base value and modulation. |
| Scenes | Optional top-level arrays kept verbatim (`effects`, `triggers`, `lfos`), with SCN-012 warning codes per entry. |
| Macros | None. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- (to be filled by /speckit-clarify)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One control moves several parameters along their own curves (Priority: P1)

A performer has a macro "Glow sweep" whose targets are the glow intensity (slow start), the glow radius
(logarithmic, reversed) and the circular spectrum's bar count. Moving the macro from 0 to 1 moves every
target at once, each following its own saved curve and range.

**Why this priority**: This is the roadmap acceptance.

**Independent Test**: Set a three-target macro to 0, 0.25, 0.5 and 1 and compare each target's value with
its own curve and range applied to that macro value.

**Acceptance Scenarios**:

1. **Given** a macro with three targets, **When** it is set to 0, 0.25, 0.5 and 1, **Then** each target
   equals its range applied to its curve of the macro value (within 1e-9, exactly at 0 and 1).
2. **Given** a reversed target, **When** the macro is 0, **Then** the target is at its range's maximum, and
   at 1 at its minimum.
3. **Given** a target range reaching outside the parameter's allowed range, **When** the macro moves,
   **Then** the target never leaves the allowed range.

---

### User Story 2 - Macros are saved with the scene and undo in one step (Priority: P1)

The macro, its value and every target's curve, range and reversal are saved in the scene and come back
exactly. One macro move undoes in one step, restoring every target together.

**Why this priority**: The acceptance names "saved" curves; undo keeps a multi-target change safe.

**Independent Test**: Save and reopen a scene with macros; move a macro and undo.

**Acceptance Scenarios**:

1. **Given** a scene with macros, **When** it is saved and reopened, **Then** the macros are identical and
   setting the reopened macro gives the same target values.
2. **Given** a scene without macros, **When** it is saved, **Then** nothing new is written.
3. **Given** a macro target naming a parameter this version does not know, or an invalid target, **When**
   the scene opens, **Then** it opens, a warning names the path, the other targets still work and the
   entry is kept for re-save.
4. **Given** a macro moved (one drag or one step), **When** the user undoes, **Then** the macro and every
   target return to their previous values in one step.

---

### User Story 3 - A macro control in the app (Priority: P2)

Settings shows a "Macros" section with one accessible slider per macro and, under it, each target's
name and current value (read-only). Moving the slider updates the labels.

**Why this priority**: Makes the macro usable and verifiable on screen; editing targets is a later row.

**Independent Test**: A UI test moves the slider and sees the target value labels change.

**Acceptance Scenarios**:

1. **Given** a scene with a macro, **When** Settings opens, **Then** a Macros section shows the macro's
   slider and its targets with their values.
2. **Given** the slider moved, **When** it settles, **Then** the target values shown change accordingly.

### Edge Cases

- A macro value outside 0…1 or not finite is limited to 0…1 (non-finite reads 0).
- An unknown parameter ID: skipped, reported; other targets still move.
- A target of a kind a macro cannot drive (on/off, color): refused as invalid, reported, skipped.
- A target the app cannot write (registered but without an app control): skipped and reported.
- Two targets on the same parameter in one macro: refused (the second is reported).
- More than 8 macros or more than 8 targets per macro: the extra ones are kept but not used, reported.
- A discrete target (enum, integer) lands on the nearest allowed value.
- Opening a scene does not re-apply its macros: the saved parameter values are restored as they were.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-010-R1**: A macro MUST have a name, a value in 0…1 and 1…8 targets; a scene holds at most 8 macros.
- **MOD-010-R2**: Each target MUST name a registered parameter and carry a MOD-004 curve, an output range
  (minimum ≤ maximum) and an optional reversal.
- **MOD-010-R3**: A target's value MUST be its range interpolated at its curve applied to the macro value
  (to 1 − value when reversed), limited to the parameter's allowed range; exact at the range ends.
- **MOD-010-R4**: Discrete targets (enum by case position, integer by step) MUST take the nearest allowed
  value; on/off and color parameters MUST be refused.
- **MOD-010-R5**: An unknown or invalid target MUST be skipped and reported; the other targets still apply.
- **MOD-010-R6**: Setting a macro MUST write the targets' base values through the same path as Settings,
  so audio modulation and the sensory safety clamp still apply on top.
- **MOD-010-R7**: A scene MUST store macros in an optional `macros` list, written only when set, kept
  verbatim (unknown fields included), with no format version change.
- **MOD-010-R8**: Invalid macros or targets and unknown target parameters MUST be reported with warnings at
  their paths; the entry is kept for re-save.
- **MOD-010-R9**: One macro change MUST be one undo step that restores the macro and all its targets.
- **MOD-010-R10**: The app MUST show a Macros section with an accessible slider per macro and read-only
  target values.
- **MOD-010-R11**: The macro model MUST be pure, deterministic and build on Linux.

### Key Entities

- **Macro**: name, value 0…1, ordered targets.
- **Macro target**: parameter ID, curve, output range, reversed or not.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-010-S1**: For a three-target macro at 0, 0.25, 0.5 and 1 every target equals its own curve and
  range (within 1e-9, exact at the ends), before and after a scene round trip.
- **MOD-010-S2**: No target ever leaves its parameter's allowed range.
- **MOD-010-S3**: Unknown or invalid targets are reported and skipped; the scene still opens.
- **MOD-010-S4**: One macro change is undone in one step.
- **MOD-010-S5**: On screen, moving the macro slider changes the target values shown, in a test under 30 s.
- **MOD-010-S6**: The affected package suites pass on macOS and Linux, each under one minute.

## Assumptions

- No macro editor is added (no binding editor exists either); macros come from scenes, and a debug seed
  creates one for tests.
- Only parameters the app can write (UIX-003's targets) can be driven in the app.
