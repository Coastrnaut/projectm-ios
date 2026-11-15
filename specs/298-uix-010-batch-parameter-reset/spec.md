# Feature Specification: UIX-010 Batch Parameter Reset

**Feature Branch**: `feature/uix-010` (spec directory `298-uix-010-batch-parameter-reset`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement UIX-010 (Batch parameter reset) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Reset selected parameters to defaults with one undo step." Acceptance, verbatim:
"Undo restores all previous values in one action." P2, size M, depends on SCN-010 and MOD-001."

Identifiers in this feature carry the roadmap ID: requirements `UIX-010-R1…`, success criteria `UIX-010-S1…`,
research decisions `UIX-010-D1…`, tasks `UIX-010-T01…`. Other features are cited by their own IDs: MOD-001
(typed parameter registry), SCN-010 (scene undo/redo), UIX-003 (parameter inspector), UIX-009 (parameter
search), MOD-012 (modulation matrix), MOD-017 (quantized changes), SCN-008 (snapshots), SCN-015 (scene lock),
ACC-005 (spoken values, announcer lanes).

## Baseline: what exists today (audit of 2026-11-15, commit `c0a89f33`)

| Question | Today |
|---|---|
| Parameters and defaults | MOD-001 `VisualParameterCatalog`: 15 descriptors (ID, name, group, unit, kind with range, declared default) in four groups. 7 of them have a Settings control and so a UIX-003 write target (`ParameterInspectorTargets`): glow on/off, intensity, radius, threshold; circular bars; linear orientation and spacing. The other 8 are read-only in this version. |
| Resetting one | UIX-003 inspector "Reset to Default" writes the declared default of one parameter through its target as one undo step and announces "<name> reset to <default>" on the parameter lane. |
| Seeing every parameter | UIX-009 Settings › Search Parameters: every catalog parameter under its group with its current value ("Read only" without a target); a row opens the inspector. |
| Undo | SCN-010 `SceneHistoryCoordinator`: observes the scene inputs; `endCoalescing()` closes the open step; `recordStep(label:)` records the current inputs as one named step (SCN-008 snapshot recall uses it for "Recall <name>": several writes, one step). A record with unchanged bytes adds nothing. Undo/redo apply a whole state. |
| Modulation | MOD-012 bindings are part of the scene inputs, separate from the base values. |
| Lock | SCN-015 `SceneLock.refusesEdit()` refuses (and announces) any scene edit while locked; every inspector target's write is already guarded by it. |
| Batch reset | **None.** |

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where does the user select several parameters? → A: In the UIX-009 parameter list (Settings › Search Parameters), which already lists every parameter by group and is the inspector's index. A "Select" button turns on a selection mode: each resettable row becomes a checkbox toggle, each group header offers "Select All" / "Deselect All", and a bottom bar offers "Reset to Defaults" with the count. The one-parameter inspector sheet keeps its own "Reset to Default".
- Q: Which parameters can be selected? → A: Those with a write target (a Settings control). Read-only rows stay visible but cannot be selected, since they cannot be changed or reset in this version.
- Q: Does a reset clear modulation bindings? → A: No. Only base values return to their registry defaults; MOD-012 bindings, MIDI mappings and macros stay. A reset that also removed routes would destroy work the user did not select.
- Q: How many undo steps does one reset make? → A: Exactly one, named "Reset <n> Parameters" ("Reset <name>" for one), whatever the number of values written. Edits before it stay their own steps. Undo restores every previous value at once; Redo resets them again.
- Q: What if every selected parameter is already at its default? → A: Nothing is written, no undo step is recorded, and the result says "Already at defaults".
- Q: What happens while the scene is locked? → A: The reset changes nothing and records nothing; the scene lock's usual refusal ("Scene locked. Unlock the scene to edit.") is reported and announced.
- Q: Are quantized changes (MOD-017) honoured? → A: No. A reset is written at once, so the one undo step holds all values; queuing some values for the next beat would split the reset across steps.

### Session 2026-11-15 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Does "Reset to Defaults" ask for confirmation first? → A: No. The reset is one undo step, so Undo is the safety net; a confirmation would add a tap to every reset without protecting anything Undo does not.
- Q: Where is Undo after a reset in the parameter list? → A: The parameter list shows the SCN-010 Undo and Redo buttons in its own toolbar (toolbar items exist only on the screen that declares them), so the reset is undone where it was made.
- Q: What happens to selection mode after a reset? → A: A reset that changed values (or was refused) ends selection mode and clears the selection; "Already at defaults" keeps the selection so the user can adjust it.
- Q: Which values count as "already at default"? → A: A value equal to the descriptor's declared default as the write target reads it back (the same comparison SCN-008 recall uses); such parameters are not written and are not counted in the label or announcement.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reset several parameters in one step (Priority: P1) — MVP

I have tuned the glow and the spectrum and want a clean start for some of them. In the parameter list I tap
Select, tick Glow Intensity, Glow Radius and Bars, and tap "Reset 3 to Defaults". All three return to their
defaults at once, VoiceOver says "Reset 3 parameters", and one Undo brings back all three values.

**Why this priority**: it is the roadmap row and its acceptance.

**Independent Test**: change two parameters, select them, reset, then Undo once: both show their previous
values.

**Acceptance Scenarios**:

1. **Given** N selected parameters away from their defaults, **When** I reset, **Then** every one equals its
   registry default and the undo history gained exactly one step, "Reset N Parameters".
2. **Given** that reset, **When** I Undo once, **Then** every one of the N parameters equals the value it had
   before the reset; **When** I then Redo, **Then** all N are at their defaults again.
3. **Given** parameters I did not select, **When** I reset, **Then** their values are unchanged.
4. **Given** modulation bindings on a selected parameter, **When** I reset, **Then** the bindings remain.

### User Story 2 - Select a whole group (Priority: P2)

**Acceptance Scenarios**:

1. **Given** selection mode, **When** I tap "Select All" on the Glow group, **Then** every resettable Glow
   parameter is selected and the header offers "Deselect All".
2. **Given** a selection, **When** I leave selection mode, **Then** the selection is cleared.

### User Story 3 - Nothing to do, or locked (Priority: P2)

**Acceptance Scenarios**:

1. **Given** selected parameters already at their defaults, **When** I reset, **Then** nothing changes, no
   undo step is added and I am told they are already at their defaults.
2. **Given** a locked scene, **When** I reset, **Then** nothing changes, no undo step is added and the lock's
   refusal is shown and announced.

### Edge Cases

- A selection with some parameters already at default: only the others are written; the step's count and
  the announcement name the parameters actually changed.
- An empty selection: the reset button is disabled.
- A search query is active: selection works on the visible rows; selected rows hidden by the query stay
  selected and are reset too (the count shows them).
- The reset closes any open slider coalescing first, so an earlier drag stays its own undo step.

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-010-R1**: The parameter list MUST offer a selection mode in which each parameter with a write target can be selected or deselected; read-only parameters MUST NOT be selectable.
- **UIX-010-R2**: Each group MUST offer "Select All" (every resettable parameter of the group) and, when all are selected, "Deselect All". Leaving selection mode MUST clear the selection.
- **UIX-010-R3**: "Reset to Defaults" MUST write each selected parameter's MOD-001 declared default, skipping parameters already at their default, and MUST leave unselected parameters and every modulation binding unchanged.
- **UIX-010-R4**: A reset that changes at least one value MUST add exactly one undo step, labelled "Reset <n> Parameters" (or "Reset <name>" for one), and edits made before it MUST stay separate steps.
- **UIX-010-R5**: Undo of that step MUST restore every reset parameter's previous value in one action; Redo MUST apply the reset again.
- **UIX-010-R6**: A reset that changes nothing MUST add no undo step and report "Already at defaults".
- **UIX-010-R7**: While the scene is locked (SCN-015), a reset MUST change nothing, add no undo step, and report the lock's refusal.
- **UIX-010-R8**: Accessibility: each selectable row MUST be one VoiceOver element with the toggle trait and a selected/not selected value; the reset button's label MUST include the count ("Reset 3 parameters to defaults"); the result MUST be announced on the parameter lane ("Reset 3 parameters").
- **UIX-010-R9**: The reset MUST be written immediately (not queued by MOD-017 quantization), so all values belong to the one undo step.
- **UIX-010-R10**: The parameter list MUST show Undo and Redo, and a reset that changed values or was refused MUST end selection mode; no confirmation is asked before a reset.

### Key Entities

- **Reset selection**: the set of selected parameter IDs (in memory only, per visit).
- **Reset result**: the IDs written, the undo step's label and the message (reset, already at defaults, or refused).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **UIX-010-S1**: After resetting N changed parameters, exactly one undo step was added, and one Undo restores all N previous values (tested for N = 2 and N = 4).
- **UIX-010-S2**: Unselected parameters and modulation bindings are unchanged by a reset in every test.
- **UIX-010-S3**: Resetting parameters already at default, or while the scene is locked, adds zero undo steps.
- **UIX-010-S4**: A user resets two parameters and undoes it in at most five taps from the parameter list (Select, two ticks, Reset, Undo).

## Assumptions

- No new saved setting: the selection is in memory only, so no UserDefaults key, backup or erase category changes.
- Only the 7 parameters with Settings controls are resettable today; new targets become resettable with no extra work.
- Layer composites (CMP-015) and effect parameters are outside the MOD-001 catalog and keep their own resets.
