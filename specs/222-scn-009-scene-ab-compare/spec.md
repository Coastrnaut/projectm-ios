# Feature Specification: SCN-009 Scene A/B Compare

**Feature Branch**: `feature/scn-009` (spec directory `222-scn-009-scene-ab-compare`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row SCN-009 (P2, size L, depends on SCN-008, integrated). Observable behavior, verbatim:
"Preview two saved scene states and switch instantly." Acceptance, verbatim: "Switch never mutates saved document
until user commits."

Identifiers carry the roadmap ID: requirements `SCN-009-R1…`, success criteria `SCN-009-S1…`, tasks
`SCN-009-T01…`, research decisions `SCN-009-D1…`. Other features are cited by their own IDs: SCN-001 (scene
document), SCN-002 (autosave), SCN-008 (snapshots), SCN-010 (undo/redo), SCN-015 (scene lock), PERF-010
(session recovery), CMP-014 (crossfade bus), MOD-017 (quantized changes), ACC-004 (announcer lanes).

## Baseline (audit of 2026-11-14, commit `31da9491`)

| Existing piece | What it does today | Use in SCN-009 |
|---|---|---|
| SCN-008 `SceneSnapshotCoordinator` | Saves, renames, deletes the current scene's snapshots (each commits the scene at once) and recalls one (writes only differing values through the Settings targets, one undo step) | A and B are chosen from its rows; the switch reuses its read/write targets and `SceneSnapshotRecallPlan` validation |
| SCN-002 `SceneAutosaveCoordinator` | Observes the live inputs, debounces edits, commits on Settings closing, background and terminate (`flushSynchronously`) | Suspended during Compare: no commit path writes; resumed against the pre-Compare inputs |
| SCN-010 `SceneHistoryCoordinator` | Observes the live inputs and records undo steps; `apply` sets a whole state through the Settings path | Suspended during Compare (records nothing, undo/redo refused); `apply` restores the pre-Compare state on Cancel |
| SCN-015 `SceneLock` | `refusesEdit()` choke point; the Settings targets refuse writes while locked | Starting Compare and committing are refused while locked; Cancel always works |
| PERF-010 held restore | After an abnormal exit, the committed scene is held and offered | A crash during Compare finds the pre-Compare document on disk |
| CMP-014 crossfade bus, MOD-017 quantizer | Cue crossfades; discrete edits queued to beat/bar/cue boundaries (recalls stay immediate, MOD-017-D8) | The switch is a cut: never crossfaded, never quantized |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: What are "two saved scene states"? → A: Two of the current scene's SCN-008 snapshots, or the current scene (as it was when Compare started) against one snapshot. A side's state is the pre-Compare values with that snapshot's usable values laid over them, so switching back and forth always reaches exactly the same two states.
- Q: What does the switch change? → A: Only what a snapshot holds (the app-held glow and spectrum parameters, SCN-008). It never touches media, the visual choice, the preset, the effect chain, text or layers.
- Q: Where is Compare started? → A: Settings › Visual, under the Snapshots rows: "Compare A/B…" opens a small sheet to pick A (Current scene or a snapshot) and B (a snapshot), then "Start Compare". Settings closes so the output is visible.
- Q: What does the user see during Compare? → A: A "Comparing A/B" bar in the visualizer's top status stack, shown with or without the controls: a large two-segment A | B toggle naming both sides and a "Done" button. VoiceOver reads the toggle as "Compare side" with value "A, <name>" or "B, <name>".
- Q: What does leaving offer? → A: "Done" asks "Finish Compare?" with "Keep A", "Keep B", "Cancel Compare" (restores the scene as it was before Compare) and "Keep Comparing" (closes the question).
- Q: What is saved while comparing? → A: Nothing. Autosave, the scene file, the snapshot list and the undo history are untouched until Keep. Any edit that was pending when Compare started is committed first, so the file on disk is the pre-Compare scene.
- Q: What does Keep write? → A: The kept side becomes the live scene, the autosave commits it once through its normal path, and the history records one undo step "Keep <name>" (undo returns to the pre-Compare scene). The snapshot list is unchanged.
- Q: Scene lock? → A: Starting Compare is refused while locked (the switch writes the same Settings targets the lock guards; a locked show's output stays as performed). If the scene is locked during Compare, the toggle and Keep are refused with the lock's message; Cancel Compare always works (it returns to the saved scene, which is not an edit).
- Q: What happens if the app is killed or backgrounded during Compare? → A: Nothing is written; at the next launch the pre-Compare scene is restored (or offered by PERF-010).
- Q: Announcements? → A: "Comparing A/B: A, <name>" on start, "A, <name>" / "B, <name>" on each switch, "Kept <name>" or "Compare cancelled" on leaving, on the library lane (ACC-004).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Switch between two looks (Priority: P1)

A performer has two snapshots of the glow and spectrum settings and wants to see which one works better with the
music. They start Compare with Snapshot 1 as A and Snapshot 2 as B and flip between them on the live output.

**Why this priority**: This is the roadmap row's behavior: preview two saved states and switch instantly.

**Independent Test**: With two snapshots, start Compare; toggling A/B changes the live values to each snapshot's
values at once, and the scene file, autosave, snapshots and undo history do not change.

**Acceptance Scenarios**:

1. **Given** snapshots S1 (intensity 0.2) and S2 (intensity 0.8), **When** Compare starts with A = S1, B = S2, **Then** the live intensity is 0.2 and the "Comparing A/B" bar shows A selected.
2. **Given** Compare is active, **When** the user toggles to B, **Then** the live intensity is 0.8 in the same frame update (no crossfade, no quantize wait) and VoiceOver announces "B, S2".
3. **Given** Compare is active, **When** the user toggles A/B 20 times, **Then** the scene file, its backup, the snapshot list and the undo history are byte-identical / unchanged.

---

### User Story 2 - Keep or cancel (Priority: P1)

After comparing, the performer keeps one side or cancels and gets the scene back exactly as it was.

**Why this priority**: The acceptance requires that nothing is saved until the user commits.

**Independent Test**: Keep B writes the scene once with B's values and adds one undo step; Cancel restores the
pre-Compare values and writes nothing.

**Acceptance Scenarios**:

1. **Given** Compare showing B, **When** the user chooses Keep B, **Then** the live scene keeps B's values, the scene file is written exactly once, and Undo is "Keep S2".
2. **Given** Compare after several toggles, **When** the user chooses Cancel Compare, **Then** every value is as before Compare and nothing is written.
3. **Given** the scene is locked during Compare, **When** the user chooses Keep B, **Then** it is refused with "Scene locked. Unlock the scene to edit." and Compare stays active; Cancel Compare still works.

---

### User Story 3 - Compare against the current scene (Priority: P2)

The performer compares what is on screen now with one snapshot.

**Independent Test**: Start Compare with A = Current scene, B = S1; A shows the pre-Compare values.

**Acceptance Scenarios**:

1. **Given** live intensity 0.5 and S1 at 0.2, **When** Compare starts with A = Current scene, **Then** nothing changes until the user toggles to B.

### Edge Cases

- Fewer than one usable snapshot: "Compare A/B…" is disabled with the hint "Save a snapshot first".
- A and B the same snapshot: Start Compare is disabled.
- A snapshot value for an unknown parameter is skipped as in a recall (SCN-008-R7).
- App killed during Compare: the next launch restores the pre-Compare scene (nothing was written).
- Background or Settings closing during Compare: no commit.
- Undo/redo (buttons or ⌘Z) during Compare: refused (nothing to undo while previewing); snapshot save, rename, delete and recall are refused with "Finish Compare first."

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-009-R1**: Settings › Visual MUST offer "Compare A/B…" under the snapshot rows, enabled when the scene has at least one usable snapshot, to choose A (Current scene or a snapshot) and B (a snapshot different from A) and start Compare.
- **SCN-009-R2**: Starting Compare MUST commit any pending autosave edit first, capture the pre-Compare state, suspend the autosave and the undo history, apply side A and close Settings. It MUST be refused while the scene is locked (SCN-015).
- **SCN-009-R3**: The A/B toggle MUST set every captured parameter to the chosen side's value at once (a cut: no crossfade, no quantize), writing only values that differ, through the Settings targets.
- **SCN-009-R4**: While Compare is active, no write MUST reach the scene file, its backup, the snapshot list or the undo history (autosave triggers, Settings closing, background and terminate included); undo, redo and snapshot edits MUST be refused.
- **SCN-009-R5**: Cancel Compare MUST restore the pre-Compare state through the history's apply path and resume autosave and history so that nothing is written when nothing else changed.
- **SCN-009-R6**: Keep A / Keep B MUST be refused while locked; otherwise set the kept side, resume, commit the scene once through the autosave's normal path and record one undo step "Keep <name>".
- **SCN-009-R7**: A "Comparing A/B" bar MUST stay in the visualizer's status stack during Compare, shown with or without the controls, with the A | B toggle and Done; Done asks Keep A, Keep B, Cancel Compare or Keep Comparing.
- **SCN-009-R8**: Start, each switch and leaving MUST be announced on the library lane (ACC-004); the toggle has label "Compare side" and value "A, <name>" / "B, <name>".
- **SCN-009-R9**: A crash or kill during Compare MUST leave the pre-Compare scene on disk, restored by the existing launch restore (SCN-002) or PERF-010's offer.
- **SCN-009-R10**: No new stored setting, scene field or file. Compare is session state in memory only.

### Key Entities

- **Compare session**: the pre-Compare inputs and parameter values, side A (current or snapshot index and name), side B, the shown side.
- **Side state**: pre-Compare parameter values overlaid with the snapshot's usable values.

## Success Criteria *(mandatory)*

- **SCN-009-S1**: 20 A/B switches leave the scene file, its backup, the snapshot list and the undo history byte-identical / unchanged (acceptance test with real stores in a temporary folder).
- **SCN-009-S2**: Cancel Compare restores every pre-Compare value exactly and writes nothing.
- **SCN-009-S3**: Keep B writes the scene exactly once, with B's values, and adds exactly one undo step.
- **SCN-009-S4**: A relaunch after a kill during Compare restores the pre-Compare scene.
- **SCN-009-S5**: A switch updates the live values in the same main-actor turn as the tap (no timed transition).
- **SCN-009-S6**: The UI test starts Compare, switches A/B and keeps B in under 30 s on the simulator.

## Assumptions

- Snapshots hold only the seven app-held parameters SCN-008 captures; Compare covers exactly those. Comparing whole scenes from the show is out of scope (the cue path already switches scenes).
- Edits made in Settings beside the output (iPad split editor) during Compare are live but unsaved; Cancel restores the pre-Compare state, Keep commits whatever is live.
- MIDI/OSC values are live performance input outside the scene and are not affected.
- Simulator results are never device evidence (Constitution X); no device task is required.
