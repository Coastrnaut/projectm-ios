# Feature Specification: SCN-010 Scene Undo and Redo

**Feature Branch**: `feature/scn-010` (spec directory `077-scn-010-scene-undo-redo`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement SCN-010 (Scene undo/redo) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Maintain bounded command history
across visual edits." Acceptance, verbatim: "Undo and redo restore ordered layer tree and
parameters." P0, size L, depends on SCN-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SCN-010-R1…`, success criteria `SCN-010-S1…`, tasks `SCN-010-T01…`. Other features
are cited by their own IDs: SCN-001 (scene document, ADR-0028), SCN-002 (scene autosave), SHOW-001
(cue list), PERF-010 (session recovery), CMP-002 (layer stack), MED-001/MED-002/MED-009 (photo,
video, text), CAM-001 (camera), OUT-010/SHOW-014 (blackout), OSC-001, FR-070 (accessibility), FR-072
(Reduce flashing).

## Baseline: what exists today (audit of 2026-11-13, commit `607c2c2`)

The row's gap status is "Gap candidate; re-audit at implementation". The audit confirms the gap:

| Needed | Today |
|---|---|
| A scene state to compare | SCN-001's canonical document bytes; semantic equality is canonical byte equality (ADR-0028 names SCN-010 as a user of it). |
| What the user edits | SCN-002's `SceneInputs`: the visual, bar count, orientation, spacing, glow on/off, intensity, radius, threshold, the Text visual's spec and the stored photo and video. The app has no free-form layer editor: each visual has a fixed ordered layer stack (CMP-002). Bindings have no editing UI. |
| History | Nothing. No undo in Settings, no keyboard shortcut, no UIKit undo manager use. |
| Scene changes that are not edits | Launch restore (SCN-002), Reopen/Start fresh (PERF-010), cue application (SHOW-001), photo or video import and removal (MED-001/002), choosing Camera (session only, CAM-001-R11). |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative, local-first option.

- Q: Should the history store whole scene states or the differences between them? → A: Whole states (snapshots): the canonical bytes of each state plus the app values that produce it. Scene documents are small, equality is byte equality (ADR-0028), and a snapshot cannot drift the way a chain of diffs can; the 4 MB budget bounds memory. Rejected: structural diffs (more code, harder to prove correct, savings irrelevant at this size); command objects with inverse operations (every future editor would need its own inverse).
- Q: Is applying a cue (or stepping through the show) an undoable edit? → A: No. Cue navigation is performance control, not editing; undoing it would fight the show's position. A cue application, launch restore, Reopen/Start fresh and a photo or video import or removal restart the history from the scene they produce (`SCN-010-R9`). Rejected: recording cue applications as steps (Undo would silently leave the show's cue); keeping the old steps across a cue (Undo would jump back to a look from another cue).
- Q: When do slider and typing changes stop merging into one step, given no wall-clock rule is allowed? → A: Consecutive changes to the same continuous control merge until a boundary: a different control changes, an undo or redo, Settings closes, or the slider drag ends. Discrete controls never merge. Rejected: a time window (non-deterministic, not testable without a clock); one step per value (a drag would need dozens of undos).
- Q: Where do the Undo and Redo controls live, and is shake to undo offered? → A: Buttons in Settings' navigation bar (where every scene edit is made; the compact visualizer controls already wrap), plus ⌘Z / ⇧⌘Z on a hardware keyboard both in Settings and on the visualizer. Shake to undo is not offered: an accidental shake during a performance must never change the look, and the history does not use the system undo manager. Rejected: buttons in the visualizer controls (crowds the grid, accidental taps on stage); system shake to undo.
- Q: How does undo interact with autosave, and does the history survive a relaunch? → A: An undo or redo changes the scene like any edit, so SCN-002 commits it under its own rules; the history lives in memory only and is empty after launch. Rejected: persisting the history (new stored data and a format to migrate for little benefit; SCN-002 already keeps the latest scene).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Undo a look change (Priority: P1)

A performer is shaping a look in Settings: they choose the Circular Spectrum, set 16 bars and raise
the glow intensity. The last change went too far. They tap Undo: the glow goes back. They tap Undo
again: the bar count goes back. The audio keeps playing throughout.

**Why this priority**: It is the row's behavior and acceptance ("undo restores ordered layer tree and
parameters").

**Independent Test**: A scripted sequence of edits, then undo one step at a time; each state equals
the state recorded before the matching edit (canonical scene bytes, including layer order and every
parameter).

**Acceptance Scenarios**:

1. **Given** edits E1…En made in order, **When** the performer undoes n times, **Then** after each
   undo the scene equals the scene before the matching edit, in reverse order, layer order and
   parameters included.
2. **Given** the audio source is running, **When** the performer undoes or redoes, **Then** the
   source is not restarted.
3. **Given** a slider drag that passed through many values, **When** the performer undoes once,
   **Then** the value returns to where the drag started.

---

### User Story 2 - Redo what was undone (Priority: P1)

After undoing two steps the performer changes their mind and taps Redo twice: the look returns to
where it was. If instead they make a new change after undoing, Redo is no longer offered.

**Why this priority**: It completes the acceptance ("undo and redo restore…").

**Independent Test**: Undo all, redo all; the final state equals the state after the last edit. A new
edit after an undo empties the redo list.

**Acceptance Scenarios**:

1. **Given** k undone steps, **When** the performer redoes k times, **Then** each redo restores the
   state after the matching edit, in order.
2. **Given** an undone step, **When** the performer makes a new edit, **Then** Redo is unavailable.

---

### User Story 3 - Know what will be undone (Priority: P2)

The Undo and Redo buttons say what they will undo or redo ("Undo Bars 16", "Redo Glow Intensity
75%") to VoiceOver, are disabled when there is nothing to undo or redo, and work from a hardware
keyboard (⌘Z, ⇧⌘Z).

**Why this priority**: Accessibility (FR-070) and iPad keyboard use; the history works without it.

**Independent Test**: After changing bars to 16, the Undo button's accessibility label is
"Undo Bars 16"; with an empty history both buttons are disabled.

### Edge Cases

- **Nothing changed**: an edit that leaves the scene equal (same canonical bytes) is not recorded,
  for example choosing the visual already shown or a change that the scene does not record.
- **Long sessions**: the history keeps at most 50 undo steps and at most 4 MB of states; the oldest
  steps are forgotten first. A state larger than the whole budget leaves only the current state.
- **Cue applied, scene reopened or restored, photo or video replaced**: these are not edits; the
  history starts again from the new scene (no undo back across them).
- **Camera shown**: Camera is session only and not part of a scene; choosing it is not an edit. An
  undo or redo that changes the visual leaves Camera exactly as a cue does; one that does not change
  the visual leaves the camera running.
- **Blacked out**: undo and redo change the look under the black cover; the output stays black.
- **Relaunch**: the history is in memory only; it is empty after launch.
- **Settings closed**: Undo and Redo keep working from the hardware keyboard on the visualizer.

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-010-R1**: The app MUST keep a history of scene edits: each step holds the scene before an edit
  as an SCN-001 scene state (its canonical bytes plus the values the app re-applies), and its label.
- **SCN-010-R2**: An undoable edit is a user change to what the current scene records: the visual
  (never Camera itself), bar count, orientation, spacing, glow on/off, intensity, radius, threshold
  and the Text visual's spec. The audio source, Reduce flashing and other safety or accessibility
  settings, the performance overlay, OSC, blackout, the camera, cue navigation, launch restore,
  Reopen/Start fresh and photo or video import or removal are not undoable edits.
- **SCN-010-R3**: An edit whose resulting scene state has the same canonical bytes as the current
  state MUST NOT be recorded.
- **SCN-010-R4**: Consecutive changes to the same continuous control (a slider: glow intensity,
  radius, threshold, text size, text outline; and typing the text message) MUST coalesce
  into one step until a boundary: a change to another control, an undo or redo, Settings closing, or
  the end of a slider drag. Discrete controls (pickers such as
  bars, orientation and spacing, toggles, the visual) never coalesce. No
  boundary depends on wall-clock time.
- **SCN-010-R5**: Undo MUST restore the state before the newest step and move that step to the redo
  list; Redo MUST restore the state after it and move it back. A new recorded edit MUST empty the
  redo list.
- **SCN-010-R6**: The history MUST be bounded: at most 50 undo steps and at most 4 MB of stored states
  (undo, redo and current counted together), evicting the oldest undo steps first, then the farthest
  redo steps.
- **SCN-010-R7**: Undo and redo MUST apply the state through the same path Settings and cues use
  (settings setters, the text coordinator, the visual switch, then the visual and glow refresh), and
  MUST NOT restart or stop the audio source.
- **SCN-010-R8**: Each undo or redo is an edit for SCN-002: autosave commits it like any other change
  (a visual change at once, others debounced). The history itself is never written to disk and is
  empty at launch.
- **SCN-010-R9**: Non-edit scene changes (R2's list) MUST restart the history from the scene they
  produce: both lists are emptied.
- **SCN-010-R10**: Settings MUST show Undo and Redo buttons, disabled when unavailable, whose
  accessibility labels name the step ("Undo Bars 16"); ⌘Z and ⇧⌘Z MUST undo and redo from a hardware
  keyboard in Settings and on the visualizer. Shake to undo is not offered.
- **SCN-010-R11**: The history model MUST be plain Swift that builds and tests on Linux, with no
  files, no networking and no clock.

### Key Entities

- **Scene state**: a scene's canonical bytes (SCN-001) and the app values that produce it.
- **History step**: the state before an edit, the edit's label and its coalescing key.
- **Scene history**: the current state, the undo list, the redo list and the limits.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SCN-010-S1** (the row's acceptance): for a scripted sequence of edits (visual, bars, glow
  intensity, text, orientation), undoing all restores every intermediate state in reverse order with
  canonical bytes equal to the recorded ones (layer order and parameters included), and redoing all
  returns to the final state (100%).
- **SCN-010-S2**: a new edit after an undo leaves nothing to redo; a no-op edit records nothing; a
  slider drag of any length undoes in one step.
- **SCN-010-S3**: with 200 edits the history holds at most 50 steps and at most 4 MB, the oldest
  forgotten first.
- **SCN-010-S4**: a fixed-seed random sequence of edits, undos and redos always matches a reference
  model, in under 1 s.
- **SCN-010-S5**: in the app (simulator), changing bars and glow in Settings then tapping Undo twice
  restores both values, Redo moves forward again, and the audio source is started exactly once.
- **SCN-010-S6**: unit tests run in about 1-2 s and at most 10 s each, each package suite in under 1
  minute; the UI test in under 30 s (owner rule 7).

## Assumptions

- The app has no free-form layer editor; the ordered layer tree changes only through the visual
  choice (CMP-002 fixed stacks). Undo restores it by restoring the visual, and the comparison uses
  the full scene document, so a future layer editor gets the same guarantees.
- Bindings have no editing UI yet; they are carried, not undone (a later binding editor records its
  edits through the same history).
- The scene document is small (well under 64 KB without embedded media), so whole-state snapshots are
  cheaper and safer than diffs.
