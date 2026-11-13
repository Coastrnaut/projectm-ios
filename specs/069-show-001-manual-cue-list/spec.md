# Feature Specification: SHOW-001 Manual Cue List

**Feature Branch**: `feature/show-001` (spec directory `069-show-001-manual-cue-list`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement SHOW-001 (Manual cue list) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Arrange scenes into a sequential
show with next and previous controls." Acceptance, verbatim: "Five-cue list advances
deterministically and preserves scene IDs." P0, size M, depends on SCN-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SHOW-001-R1…`, success criteria `SHOW-001-S1…`, tasks `SHOW-001-T01…`. Other
features are cited by their own IDs: SCN-001 (scene document, ADR-0028), SCN-002 (scene autosave,
in progress in parallel), FILE-001 (scene archive), SHOW-014 and OUT-010 (blackout), CAM-001
(camera is session only), MED-001/MED-002/MED-009 (photo, video, text), FR-065 (what the app may
store), FR-070 (accessibility).

## Baseline: what exists today (audit of 2026-11-13, commit `fb28723`)

The row's gap status is "Gap candidate; re-audit at implementation". The audit confirms the gap:

| Needed | Today |
|---|---|
| A show (ordered cues) | Nothing: no cue, show or timeline type anywhere in `Packages/` or the app. |
| Scenes to arrange | SCN-001 defines the scene document (stable scene ID, name, layers, parameters, bindings, assets) and its live state; FILE-001 exports and imports one scene. There is no scene library (SCN-004 to SCN-006 are later rows) and no saved "current scene" on this branch (SCN-002 is in progress). |
| Applying a scene to the live output | The app's visual is chosen in Settings (projectM, Circular, Linear, Camera, Photo, Video, Text) with its options (bars, orientation, spacing, glow, text). Changing them switches the visual without touching the audio source (VIS-001, VIS-002). No code turns a scene document into these choices yet. |
| Next/Previous for a show | The controls' Next/Previous walk presets, not scenes. |

Later SHOW rows build on this one and shape its model: timed advance (SHOW-002), beat-quantized
advance (SHOW-003), per-cue transition override (SHOW-004), hold and skip (SHOW-005), rehearsal
preview (SHOW-006), timeline transport (SHOW-007), cue notes (SHOW-012), scene rotation (SHOW-013),
performance lock (SHOW-015) and OSC cue sync (OSC-012). This row delivers only the manual list.

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative, local-first option.

- Q: What should Next do on the last cue, and Previous on the first: stop or wrap around? → A: Stop. Next on the last cue and Previous on the first cue (or at Standby) do nothing and the button shows unavailable; the result says "at end" or "at start". A live show must never jump from its finale back to its opening on an extra press; wrapping is a later automation choice (SHOW-013 rotation). Rejected: wrap (an accidental press shows cue 1 to the audience); stop and blank (blanking is SHOW-014's job).
- Q: How does a cue refer to its scene while there is no scene library? → A: By scene ID. The show is its own versioned file; each scene the show uses is an SCN-001 document stored next to it in the show's folder under its scene ID, captured (a snapshot with a new scene ID) when the cue is added. Two cues may share a scene ID. When the scene library arrives (SCN-004 to SCN-006) cues keep the same scene IDs and the folder copies move into the library. Rejected: embedding scenes inside the show file (one huge file, rewritten on every cursor move; scenes not reusable by ID); referring to the live "current scene" (SCN-002), which changes after the cue is made.
- Q: Is the show's position saved, and is the active cue shown again at launch? → A: The position is saved with the show (Standby or the active cue's ID), so a relaunch mid-show keeps its place; the cue is not applied again at launch: the app shows what it restores today (and SCN-002's current scene once merged, which is the last applied cue's look). Rejected: not saving the position (a crash mid-show restarts at Standby); applying the cue at launch (a launch would silently change the look).
- Q: Where are the show's Next and Previous controls? → A: In the visualizer's controls, as a show row above the buttons (Previous cue, "Cue 2 of 5 · Intro", Next cue), shown only when the show has at least one cue and hidden with the controls; the arrow and page keys (a keyboard or presentation clicker) work whether or not the controls are shown. The editor (add, reorder, rename, delete, Go to cue) is in Settings → Show. Rejected: a persistent on-screen cue bar (covers the visualization on the device; the emergency control is the only persistent one, SHOW-014); a separate full-screen show mode (too large for this row).
- Q: What happens when a step lands on a cue whose scene is missing or invalid: skip to the next good cue, or stop on it? → A: Stop on it: the position moves to that cue (so counting presses stays predictable and deterministic), the output is left unchanged, a non-blocking notice says "Cue 3: the scene could not be shown" and VoiceOver announces it; the editor flags the cue. Rejected: skipping (one press would move by a varying number of cues, breaking the operator's count and the determinism criterion); refusing to move (the show would be stuck on a damaged cue).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Step through a prepared show (Priority: P1)

A performer has prepared five cues, each a different scene. During the show they press Next to go
from cue to cue, and Previous to go back one. Each press shows the cue's scene at once; the music
keeps playing.

**Why this priority**: It is the row's behavior and its acceptance.

**Independent Test**: With a seeded five-cue show standing on cue 1, Next four times shows cues 2, 3,
4 and 5 (label and scene); Previous returns to cue 4; the audio source was started once.

**Acceptance Scenarios**:

1. **Given** a five-cue show standing on cue 2, **When** the performer presses Next, **Then** cue 3
   is active, its scene is shown and the cue label reads "Cue 3 of 5".
2. **Given** the show stands on cue 5, **When** the performer presses Next, **Then** nothing changes
   (the show stops at its end) and Next is shown unavailable.
3. **Given** the show stands on cue 1, **When** the performer presses Previous, **Then** nothing
   changes and Previous is shown unavailable.
4. **Given** the same five-cue show and the same sequence of Next, Previous and Go to cue presses,
   **When** it is played twice from the same starting state, **Then** both runs show the same cue and
   the same scene at every step.

---

### User Story 2 - Build the show (Priority: P1)

Before the show the performer sets up a look (visual and its options), adds it as a cue, changes the
look, adds another, and so on. They reorder cues, rename them and delete one they no longer need.

**Why this priority**: Without building a show there is nothing to step through.

**Independent Test**: In the show editor, add the current scene three times with different visuals,
move the last cue to the top, rename one, delete one; the list, the labels and each cue's scene are as
expected after relaunching the app.

**Acceptance Scenarios**:

1. **Given** the Circular Spectrum is shown, **When** the performer chooses Add Current Scene,
   **Then** a cue is appended at the end of the show, labelled after the visual, holding a snapshot of
   the current look.
2. **Given** a show with cues, **When** the performer moves, renames or deletes a cue, **Then** the
   output does not change and the change is kept after relaunch.
3. **Given** a cue added earlier, **When** the performer later changes the visual's options, **Then**
   the cue still holds the look it captured.

---

### User Story 3 - Cues are safe during a blackout and from a keyboard (Priority: P2)

During a show the performer may black out (SHOW-014) and step to the next cue in the dark, then
restore onto the new cue. On an iPad with a keyboard or a presentation clicker they step with the
arrow or page keys.

**Why this priority**: Live-show safety and the common way to drive cues; small additions.

**Independent Test**: Black out, press Next: the output stays black; Restore: the new cue's scene
fades in. The arrow keys move the show like the buttons.

**Acceptance Scenarios**:

1. **Given** the output is blacked out, **When** the performer presses Next, **Then** the cue
   changes, the output stays black, and Restore shows the new cue's scene.
2. **Given** a hardware keyboard and the visualizer, **When** the performer presses Right Arrow or
   Page Down, **Then** the show advances as with Next; Left Arrow or Page Up goes back as with
   Previous; B keeps its blackout meaning (SHOW-014).

---

### Edge Cases

- **Empty show**: no show controls are shown in the visualizer; Next and Previous keys do nothing.
- **Standby**: a new show (or one whose active cue was deleted while it was the first) stands before
  cue 1 ("Standby"); Next goes to cue 1; Previous does nothing.
- **Deleting the active cue**: the output keeps showing what it shows; the show stands on the cue
  before the deleted one (or Standby), so Next plays the cue that followed the deleted one.
- **Missing or unreadable scene**: a cue whose scene cannot be found or read is flagged in the editor
  ("Scene missing"); stepping onto it moves the show to that cue, leaves the output unchanged and
  shows a short notice. The rest of the show works.
- **Scene asset no longer stored**: a cue's scene names a photo or video that is no longer the stored
  one; the cue applies its visual with the photo or video the app holds now and says so in a notice.
- **Camera**: a cue never starts the camera. A captured look records the visual chosen before Camera
  (CAM-001: Camera is session only); a scene with a camera layer is applied without it (the visual
  chosen before Camera, or projectM), with a notice.
- **projectM**: a cue for projectM switches to projectM and keeps the current preset (a scene does
  not record a preset today).
- **Show file damaged, too large or from a newer version**: the file is set aside unchanged (never
  deleted), the app starts with an empty show and says so once in the editor.
- **Saving fails (disk full)**: the change stays in effect for the session, the editor says the show
  could not be saved, and the previous files stay intact (each file is written whole).
- **Duplicate cue IDs in a stored file**: the file is refused as damaged (above).
- **Limits**: at most 256 cues; a label is 1 to 80 characters (trimmed); adding beyond the limit is
  refused with a message.
- **Same scene twice**: two cues may reference the same scene ID.
- **Settings or another sheet open**: the show keys do nothing (the sheet takes the keyboard, like B
  in SHOW-014).

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-001-R1**: The app MUST hold one show: a name and an ordered list of at most 256 cues. Each
  cue has a stable cue ID that never changes, the scene ID of the scene it shows, and a label.
- **SHOW-001-R2**: The show MUST have a position: Standby (before the first cue) or one active cue,
  identified by its cue ID. The position MUST be saved with the show.
- **SHOW-001-R3**: Next MUST move from Standby to cue 1 and from cue n to cue n + 1; at the last cue
  it MUST do nothing (no wrap). Previous MUST move from cue n to cue n − 1; at cue 1 and at Standby it
  MUST do nothing. Neither does anything for an empty show.
- **SHOW-001-R4**: Go to cue MUST make any cue active and show its scene, including the active one
  (which shows its scene again).
- **SHOW-001-R5**: Stepping MUST be deterministic: the same operations from the same show and
  position MUST always give the same position and the same scene ID, with no dependence on time,
  randomness or device.
- **SHOW-001-R6**: Adding, moving, renaming and deleting cues MUST NOT change the output. The position
  follows the active cue's ID through moves. Deleting the active cue makes the cue before it active
  without showing it (Standby if it was first).
- **SHOW-001-R7**: Add Current Scene MUST store a snapshot of the shown look (visual and its options,
  text overlay, the stored photo or video it uses) as a new scene with a new scene ID and append a cue
  for it, labelled with the visual's name. Camera records the visual chosen before Camera.
- **SHOW-001-R8**: When a cue becomes active by Next, Previous or Go to cue, its scene MUST be read
  and validated (SCN-001) and its look applied to the live output: the visual and its options and
  text. The audio source MUST NOT be stopped or restarted. A cue MUST NOT start the camera. Layers
  the app cannot draw (camera, materials, generator graphs, unknown kinds) are left out of the applied
  look with a notice; SCN-001 warnings (for example a photo no longer stored) do not stop the apply.
- **SHOW-001-R9**: If a cue's scene is missing, unreadable or invalid (SCN-001 errors), the show MUST still move to
  the cue, the output MUST stay unchanged, and a non-blocking notice and a VoiceOver announcement MUST
  say the cue's scene could not be shown.
- **SHOW-001-R10**: While the output is blacked out (OUT-010, SHOW-014), stepping MUST keep the output
  black; Restore shows the active cue's scene.
- **SHOW-001-R11**: A stored show MUST be validated on load: an unknown format, a newer version, a
  file over 1 MiB, more than 256 cues, duplicate cue IDs or a malformed cue refuse the whole file,
  which is set aside without deletion; the app then starts with an empty show and the editor says so.
  A cue whose scene is not stored is kept and flagged, not refused.
- **SHOW-001-R12**: The show and its scenes MUST be saved on the device after every change, each file
  written whole (never half written). A scene is stored before a cue refers to it, keeps its scene ID
  byte for byte, and is removed when no cue refers to it any more.
- **SHOW-001-R13**: The visualizer's controls MUST show (hidden with them), when the show has at least one cue, Previous
  cue and Next cue buttons and the active cue's position and label ("Cue 2 of 5 · Intro", or
  "Standby · 5 cues"), with VoiceOver labels and the value "Cue 2 of 5, Intro"; a button that would do
  nothing is shown unavailable (FR-070). A step's result notice (missing scene) shows for about 4 s
  and is announced to VoiceOver.
- **SHOW-001-R14**: Settings MUST offer a show editor: the cue list with each cue's number, label and
  a flag for a missing scene; Add Current Scene; reorder; delete; rename; Go to cue.
- **SHOW-001-R15**: On the visualizer, Right Arrow and Page Down MUST act as Next cue, Left Arrow and
  Page Up as Previous cue, without modifiers, whether or not the controls are shown, when the show
  has at least one cue. They MUST NOT use B (SHOW-014) and do nothing while a sheet is open.
- **SHOW-001-R16**: The show stays on the device: no network use, nothing leaves the app except as
  the user's own device backups; it stores only cue labels, scene settings and references to the
  app's stored photo and video (FR-065 is extended by this feature and the privacy policy updated).

### Key Entities

- **Show**: format name and version, show ID, name, ordered cues, position (Standby or the active cue
  ID).
- **Cue**: cue ID (stable), scene ID, label.
- **Show scene**: an SCN-001 scene document stored with the show under its own scene ID.
- **Step result**: the new position and scene ID, and whether anything changed (moved, at the end, at
  the start, empty).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHOW-001-S1**: For a five-cue show with five distinct scenes, a scripted sequence of at least 15
  Next, Previous and Go to cue steps gives exactly the expected position and scene ID at every step,
  and two runs from fresh, identical states give identical results (100%).
- **SHOW-001-S2**: Saving and loading a show keeps every cue ID, scene ID, label, the order and the
  position exactly, and each stored scene keeps its scene ID (100%).
- **SHOW-001-S3**: A fixed-seed sequence of 1,000 random edits and steps keeps the show valid at
  every step (no duplicate cue IDs, the position is Standby or an existing cue, at most 256 cues), and
  replaying it gives the same final show.
- **SHOW-001-S4**: In the app (simulator), Next four times from cue 1 shows cues 2 to 5 with their
  labels and scene IDs, Previous returns to cue 4, and the audio source was started once.
- **SHOW-001-S5**: Stepping while blacked out leaves the output black in 100% of runs.
- **SHOW-001-S6**: Every unit test of this feature runs in at most 10 s and its package suite in under
  1 minute; the UI test in under 30 s (owner rule 7).

## Assumptions

- There is no scene library yet. The show keeps its own copies of the scenes it uses, next to the
  show; SCN-004 to SCN-006 (library, collections) will let cues refer to library scenes by the same
  scene IDs.
- SCN-002 (autosave) is being built in parallel. If its restore path is not integrated when this row
  is, this row applies a scene through a small path of its own, recorded as a follow-up to unify.
- One show per app is enough for this row; multiple shows, show import/export and cue notes
  (SHOW-012) are later work.
- The app stores one photo and one video at a time (MED-001, MED-002); a scene refers to them by
  store ID and does not copy them.
- Applying a scene is instant (no transition); transitions are SCN-007 and SHOW-004.
- Device checks are not needed for this row's acceptance (deterministic logic plus a simulator UI
  test); simulator results are not performance evidence.
