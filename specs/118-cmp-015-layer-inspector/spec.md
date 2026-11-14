# Feature Specification: CMP-015 Layer Inspector

**Feature Branch**: `feature/cmp-015` (spec directory `118-cmp-015-layer-inspector`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement CMP-015 (Layer inspector) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Expose per-layer controls with undo and contextual help." Acceptance,
verbatim: "Selecting different layers shows correct parameters and undo restores prior value."
Verification: unit tests, snapshots, GPU performance. P1, size M. Depends on CMP-002 (layer stack);
works with CMP-003 to CMP-007 (opacity, blend, transform, fit, mask), CMP-011 (groups), CMP-012 (solo
and mute), CMP-013 (render caching), SCN-001 (scene format), SCN-002 (autosave), SCN-010 (undo) and
MOD-001 (parameter registry)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-015-R1…`, success criteria `CMP-015-S1…`, tasks `CMP-015-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `d53cee03`)

This is the first screen that edits a layer stack. Earlier rows built the engine and left the UI here.

| Area | Today | Gap for this row |
|---|---|---|
| Visuals built as compositor stacks | Four hosts build a fixed two-layer stack, bottom first: Camera `[camera, spectrum.circular]`, Photo `[photo, spectrum.circular]`, Video `[video, spectrum.circular]`, Text `[spectrum.circular, text]`. Every entry keeps the default composite (opacity 1, normal, identity, no fit, no mask). | Nothing ever sets a layer's composite in the app. |
| Visuals that are not stacks | projectM, Oscilloscope (no layer), Circular and Linear Spectrum (one layer drawn directly by the native spectrum host, without the compositor). | A composite on these layers could not be drawn. |
| Scene layers (SCN-001, SCN-002) | The autosave captures the current scene from the app's scene inputs: the visual's fixed layers plus layers the app carries but does not draw (materials, generator graphs, unknown kinds), kept verbatim. A carried app layer's composite (from a restored document) is written back, but never applied to the host. Groups are not written by the autosave capture. | The saved composite of a drawn layer is invisible on screen; no way to change it. |
| More than one user-editable layer? | **No.** No live scene has any user-editable layer composite. A Photo, Video or Text scene has two drawn layers; a restored or seeded document can add carried layers. | The inspector makes the drawn layers of the Photo, Video and Text scenes editable. |
| Undo (SCN-010) | Whole-document snapshots over the scene inputs; per-control coalescing; Undo/Redo in Settings and Cmd-Z. | Layer edits must become scene inputs to be undoable and saved. |
| Solo and mute (CMP-012) | A transient compositor overlay; "CMP-015 will add the buttons". No app UI. | Buttons in the inspector; never saved, never undoable. |
| Blend modes (CMP-004, ADR-0037) | Six modes in the compositor and the format; "no picker". | A picker. |
| Help text | Footers written inline per Settings section. | One table for the inspector's parameters. |
| ACC-005 slider helper | Not in this base (running in parallel). | Use the same adjustable-action pattern; note it for ACC-005. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Inspect the current scene's layers (Priority: P1) 🎯 MVP

From Settings, the user opens "Layers" and sees every layer of the current scene in stack order, top
first. Selecting a layer shows all its parameters with their current values; selecting another layer
shows that layer's values.

**Why this priority**: it is the acceptance's first half and the base of every other story.

**Independent Test**: seed a scene of three layers with distinct values; select each layer in turn
and read the shown values.

**Acceptance Scenarios**:

1. **Given** a Photo scene with a photo, the spectrum and a carried material layer, **When** the user
   opens Layers, **Then** three rows are listed top first (material, spectrum, photo), each with its
   kind name and position.
2. **Given** that list, **When** the user selects each layer in turn, **Then** the detail shows that
   layer's opacity, blend mode, transform, fit (photo and video only) and mask exactly as the scene
   records them.
3. **Given** a layer the app does not draw (material, generator graph, unknown kind) or a scene whose
   visual draws its layer without the compositor (Circular or Linear Spectrum), **When** it is
   selected, **Then** its values are shown read-only with the reason.

---

### User Story 2 - Edit a layer, with undo (Priority: P1)

The user changes a drawn layer's opacity, blend mode, position, scale, rotation, fit and anchor, or
mask; the visual shows the change at once and the scene saves it. Undo restores the previous value in
the inspector and on screen; one slider drag is one undo step.

**Why this priority**: the acceptance's second half.

**Independent Test**: change opacity and transform of layer 2, Undo, compare the values and the
rendered frame with those before the edit.

**Acceptance Scenarios**:

1. **Given** the Photo scene, **When** the user drags the spectrum's opacity slider from 100 % to
   40 %, **Then** the visual shows the spectrum at 40 % and one undo step "Spectrum Opacity 40%" exists.
2. **Given** that edit and a position change, **When** the user taps Undo twice, **Then** the
   inspector shows the prior values and the rendered frame equals the frame before the edits.
3. **Given** an edit, **When** the scene autosaves and the app relaunches, **Then** the edit is
   restored on the layer and on screen.

---

### User Story 3 - Contextual help (Priority: P2)

Every parameter has a short explanation, shown as a footer under its control group and in a "?"
popover next to it, so the user can learn what opacity, a blend mode, fit or a mask does.

**Independent Test**: a table test asserts each parameter has non-empty help; a UI test opens one
popover.

**Acceptance Scenarios**:

1. **Given** the detail of a layer, **When** the user taps "?" next to Blend mode, **Then** a popover
   explains blend modes in plain words.

---

### User Story 4 - Solo and mute from the inspector (Priority: P2)

Each row has Solo and Mute buttons that hide or isolate layers for checking. They never change the
saved scene and never enter undo.

**Independent Test**: solo a layer, check the undo list and the saved scene are unchanged, and the
compositor hides the other layers.

**Acceptance Scenarios**:

1. **Given** the Photo scene, **When** the user solos the photo, **Then** only the photo is drawn,
   Undo stays as it was and the saved document is byte-identical.
2. **Given** a solo, **When** the visual changes, **Then** solo and mute are cleared.

### Edge Cases

- No current compositor scene (projectM, Oscilloscope): the inspector says the visual has no editable
  layers and lists none, or lists the one native-spectrum layer read-only.
- Camera shown: the scene records the visual chosen before Camera; the inspector shows that scene and
  its edits apply when that visual is shown (Camera itself is session only).
- A saved blend mode, fit or mask this version does not draw: shown as "Other (name)", read-only until
  the user picks a known value; it is never rewritten by merely viewing.
- A polygon mask: shown as "Polygon (N points)"; size, feather and invert stay editable, the points
  are kept.
- The photo or video is replaced (the history restarts, SCN-010-R9): composites stay.
- VoiceOver and accessibility text sizes: every control is labelled and adjustable; rows stack.

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-015-R1**: The system MUST offer a Layers screen from Settings listing the current scene's
  layers (the layers the scene saves) in stack order, top first, and its groups when present.
- **CMP-015-R2**: Selecting a layer MUST show its opacity, blend mode, transform (position X and Y,
  scale, rotation), fit mode and anchor (photo and video), mask (shape, size, corner radius, feather,
  invert), group membership, and the layer's own MOD-001 parameters the app holds (read-only).
- **CMP-015-R3**: Layers drawn by a compositor visual (photo, video, text and the circular spectrum in
  the Photo, Video and Text scenes) MUST be editable; every other layer MUST be read-only with its
  reason.
- **CMP-015-R4**: An edit MUST apply to the shown visual from the next frame through the compositor's
  stack apply, without re-rendering a cached layer for a placement change (CMP-013).
- **CMP-015-R5**: An edit MUST be part of the current scene: saved by the autosave and restored at
  launch and Reopen, and written into the document's layer composite.
- **CMP-015-R6**: Every edit MUST go through the scene history; a slider drag (or a continuous
  adjustment of one control) MUST be one undo step; Undo and Redo MUST restore the exact prior value
  in the model and on screen.
- **CMP-015-R7**: Each parameter MUST have contextual help from one table, shown as a "?" popover and
  section footers.
- **CMP-015-R8**: Solo and mute buttons MUST be offered per layer and group; they MUST NOT enter the
  scene, the autosave or the history, and MUST be cleared when the visual changes.
- **CMP-015-R9**: Unknown saved values (blend, fit, mask) MUST survive viewing and unrelated edits.
- **CMP-015-R10**: Every control MUST have an accessibility label and value; sliders MUST support
  VoiceOver increment and decrement; layouts MUST work at accessibility text sizes; solo and mute
  changes MUST be announced through the shared announcer; any animation MUST follow the motion policy.
- **CMP-015-R11**: The new views MUST type-check under the project's long-body thresholds (300 ms per
  function, 150 ms per expression).

### Key Entities

- **Layer composite edit**: the scene's composite for one drawn layer kind (opacity, blend name,
  transform, fit, mask), part of the scene inputs.
- **Inspector row**: one layer or group of the current scene: identity, kind name, position, values,
  editability and reason.
- **Help entry**: a parameter's title and explanation.
- **Solo/mute state**: transient per-kind flags for the shown visual.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-015-S1**: For a three-layer scene, selecting each layer shows 100 % of its recorded values.
- **CMP-015-S2**: After editing opacity and transform of layer 2 and undoing, the values equal the
  prior values exactly and the rendered frame equals the frame before the edit pixel for pixel.
- **CMP-015-S3**: One continuous slider adjustment produces exactly one undo step.
- **CMP-015-S4**: 100 % of inspector parameters have help text.
- **CMP-015-S5**: Solo and mute leave the undo list and the saved scene bytes unchanged.
- **CMP-015-S6**: A placement edit re-renders no cached layer picture.
- **CMP-015-S7**: No new view function exceeds the type-check thresholds.

## Assumptions

- The layer stacks stay the hosts' fixed stacks; adding, removing and reordering layers is a later
  row. Groups are listed read-only (no live scene has groups today).
- Composite edits are keyed by layer kind, because each scene has at most one layer of each drawn
  kind; the circular spectrum's composite is shared by the Photo, Video and Text scenes, as the
  autosave already matches carried layers by kind.
- Show cues keep capturing only the look they capture today; carrying composites in cues is a
  follow-up.
- Simulator results are never device evidence; GPU timing on devices is not part of this run.
