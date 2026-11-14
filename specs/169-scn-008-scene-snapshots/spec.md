# Feature Specification: SCN-008 Scene Snapshots

**Feature Branch**: `feature/scn-008` (spec directory `169-scn-008-scene-snapshots`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row SCN-008 (P1, size M, depends on SCN-001, integrated). Observable behavior,
verbatim: "Capture named parameter snapshots inside a scene." Acceptance, verbatim: "Recall restores
mapped values without reloading media assets."

Identifiers carry the roadmap ID: requirements `SCN-008-R1…`, success criteria `SCN-008-S1…`, tasks
`SCN-008-T01…`, research decisions `SCN-008-D1…`. Other features are cited by their own IDs: SCN-001
(scene document), SCN-002 (scene autosave), SCN-010 (undo history), SCN-012 (validation report), MOD-001
(parameter registry), MOD-006/MOD-007 (optional verbatim scene lists), UIX-003/UIX-004 (inspector write
path), FX-020 (effect chain), MED-001/MED-002/MED-006/MED-010 (photo, video, slideshow, logo), ACC-004
(announcer lanes), FILE-005 (library backup), FR-070 (accessibility).

## Baseline: what exists today (audit of 2026-11-14, commit `b4fe9515`)

| Area | Today |
|---|---|
| Scene document (SCN-001) | `SceneDocument`: layers, `parameters` (MOD-001 values by ID, `{"kind": …, "value": …}`), bindings, modulation, assets, groups, and the optional verbatim lists `effects` (FX-020), `triggers` (MOD-006), `lfos` (MOD-007), each written only when set so older scenes keep their bytes; unknown top-level fields kept in `extra`. Slideshow and logo live in assets (MED-006, MED-010). |
| Optional-field rule | An entry is an object kept verbatim (`fields`); `read` turns entries into live values and reports unusable ones as warnings at their path (`invalidTrigger`/`unknownTrigger`, `invalidLFO`/`unknownLFO`); the decoder counts entries before typed decoding (`tooMany`). SCN-012 classifies each code in `SceneRepairReport.classify`. |
| Current scene (SCN-002) | `SceneAutosaveCoordinator` holds a private `SceneAutosaveCarry` (what the app does not own, including triggers and LFOs as stored) and commits `SceneAutosaveCapture.document(inputs, carry:)`. `SceneInputs` is what Settings edits; `SceneRestoredValues` is what a restore applies. Cues (SHOW-001) apply their own scene files to Settings; the current scene's carry is not replaced by a cue. |
| App-held registry parameters (MOD-001) | Seven: `effect.bloom.enabled`, `.intensity`, `.radius`, `.threshold`, `visual.circularSpectrum.barCount`, `visual.linearSpectrum.orientation`, `.spacing` (`SceneAutosaveCapture.appParameterIDs`, `ParameterInspectorTargets.inspectableIDs`). |
| Write path (UIX-003/UIX-004) | `ParameterInspectorTargets.target(for:settings:)` gets/sets each through the same `AppSettings` properties Settings binds; `VisualizerView`'s `onChange` then runs `glowSettingsChanged()`/`visualSettingsChanged()`. `ParameterInspectorReset` makes one undo step with `endCoalescing()` before and after. |
| Undo (SCN-010) | `SceneHistoryCoordinator` records `SceneInputs` changes (bytes over a fixed carry snapshot); several changes in one record are labelled "Scene"; undo applies through `applySceneInputs` (Settings path; media not undone). |
| Media | Photo content (`PhotoVisualHost.content`, decode on set), video content and loop region (`VideoVisualHost`), logo (`LogoCoordinator.setLogo`), slideshow pictures. A glow or spectrum option change touches none of them. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: What does a snapshot hold? → A: A name and a set of `{parameterID: value}` for the MOD-001 registry parameters the app writes through Settings (the seven above). Rejected for this row: the FX-020 effect chain values (grade, trails), layer composites, text, media, the visual and the preset; a snapshot never names them, so recall cannot touch them.
- Q: Where is it stored? → A: In the scene document as an optional top-level `snapshots` array, written only when set (format version stays 1; scenes without it keep their bytes). Each entry is an object kept verbatim: `{"name": "S1", "values": {"effect.bloom.intensity": {"kind": "continuous", "value": 0.2}, …}}`, values in the same form as the document's `parameters`. Unknown fields in an entry are kept.
- Q: How many? → A: 16 usable snapshots per scene. The decoder accepts up to 64 entries (more refuse the file as `tooMany`, like other lists); entries past the 16th are kept but not used, with a warning. Saving a 17th is refused with a message. A snapshot holds at most 64 values.
- Q: What does SCN-012 report? → A: Two new warning codes: `invalidSnapshot` (an entry that is not usable: missing or wrong name, values not an object, a malformed value, too many values, or beyond the limit) and `unknownSnapshotParameter` (a value whose parameter ID the registry does not know; that value is skipped on recall, the rest of the snapshot works). Both keep the entry verbatim; neither refuses the scene.
- Q: What does Save Snapshot capture? → A: The current manual values of the seven parameters (what Settings shows, not the modulated values), under the next free default name "Snapshot N" (smallest unused N ≥ 1). Names are 1…64 characters after trimming spaces and are unique in a scene (compared case-insensitively).
- Q: How does Recall apply values? → A: Through the Settings write path (`ParameterInspectorTargets`), in parameter-ID order, writing only values that differ from the current ones, after validating each against the registry (MOD-001 clamping; a rejected value is skipped). It is one undo step labelled "Recall <name>". It never reloads or touches media, the visual, the preset, the effect chain, text or layers.
- Q: Missing parameters? → A: A value whose ID the registry does not know, or that the app has no control for, is skipped and reported: the status line and the announcement say "Recalled S1; 1 value skipped", and the row lists the skipped IDs.
- Q: Is recall eased over the scene's transition curve? → A: No: recall applies at once, exactly as a Settings edit. Easing would need the transition bus in the live renderer (SCN-007's follow-up); recorded as out of scope.
- Q: Where is the UI? → A: A "Snapshots" section in Settings, right below the visual options (the glow and spectrum controls a snapshot holds), for the current scene. Actions: Save Snapshot; per row Recall, Rename, Delete (swipe, context menu and VoiceOver actions). Delete asks for confirmation. Announcements go on the library lane (`AccessibilityAnnouncer`, kind `.library`).
- Q: Triggers? → A: MIDI/OSC recall is a later row; this row reserves the action ID `scene.snapshot.recall` only.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Are Save, Rename and Delete undoable? → A: No. SCN-010's history covers `SceneInputs` (the live look); the snapshot list is scene content like triggers and LFOs. These edits commit the current scene at once (SCN-002 `commitNow`). Only Recall, which changes the look, is an undo step.
- Q: Which scene's snapshots are listed? → A: The current scene (SCN-002's autosaved document). Cue scene files keep their `snapshots` verbatim through load and save; applying a cue does not change the current scene's list (as today, a cue does not replace the current scene's carried content).
- Q: What if a recalled value is equal to the current one? → A: It is not written (no `onChange`, no work); if nothing differs, recall records no undo step and says "S1 is already applied".
- Q: Do snapshots survive backup? → A: Yes: they are part of the scene document, which FILE-005 backs up as bytes; no backup change is needed.
- Q: New settings keys? → A: None.
- Q: How is "no media reload" proven? → A: A DEBUG media-load spy counts photo content sets and preloads, video content and loop-region sets, logo sets and photo/video host creations; the acceptance tests assert the counts do not change across recall and that the scene's media inputs (photo, video, logo, slideshow, visual) are identical.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I recall a saved look without the photo reloading (Priority: P1) — MVP

A VJ shows a photo with a glowing spectrum, sets Glow intensity 20 % and radius 5 %, and saves snapshot
"S1". They change both values, then recall S1: the values are back exactly, the photo is not decoded
again and nothing else in the scene changes. Undo puts the changed values back in one step.

**Independent Test**: An app unit test wires the snapshot coordinator to real `AppSettings`, the real
write targets and a real SceneHistoryCoordinator over a scene with a photo; a media-load spy counts zero.

**Acceptance Scenarios**:

1. **Given** a scene with a photo and Glow intensity 0.2, radius 0.05, **When** S1 is saved, both values changed and S1 recalled, **Then** intensity is exactly 0.2 and radius exactly 0.05, the media spy shows zero reloads (no photo decode, video seek or logo upload) and the visual and media inputs are unchanged.
2. **Given** that recall, **When** Undo runs once, **Then** both changed values return (one step, labelled "Recall S1").
3. **Given** the Settings UI, **When** a snapshot is saved, a value changed and the snapshot recalled, **Then** the value label shows the saved value again (UI test under 30 s).

---

### User Story 2 - Snapshots stay with the scene and files stay safe (Priority: P1)

**Independent Test**: SceneFormat tests (host and Linux).

**Acceptance Scenarios**:

1. **Given** a scene with snapshots, **When** it is encoded, decoded and encoded again, **Then** the bytes are identical and the snapshots are equal; unknown entry fields are kept.
2. **Given** a scene without snapshots, **When** it is read and written, **Then** its bytes are unchanged.
3. **Given** a snapshot naming an unknown parameter, **When** the scene is validated and the snapshot recalled, **Then** `unknownSnapshotParameter` is reported, that value is skipped and reported, and the other values apply.
4. **Given** 16 snapshots, **When** a 17th is saved, **Then** it is refused; **Given** a file with 17 entries, **Then** the 17th is kept but not used, with `invalidSnapshot`.
5. **Given** the current scene with snapshots, **When** the app commits it and restores it (relaunch), **Then** the snapshots come back identical.

---

### User Story 3 - I manage snapshots with VoiceOver (Priority: P2)

**Acceptance Scenarios**:

1. **Given** a snapshot row, **When** VoiceOver focuses it, **Then** it reads the name and "7 values", and offers the actions Recall, Rename and Delete.
2. **Given** a recall, **Then** VoiceOver announces "Recalled S1" on the library lane.

### Edge Cases

- A rename to an empty name, a name over 64 characters or a name already used is refused with a message; the name is unchanged.
- An unusable entry (from a newer app or a damaged file) is listed as "Can't be used" with Recall disabled; Rename and Delete still work on it, and Rename keeps its other fields.
- Recall while a glow value is MIDI- or audio-modulated sets the manual value, as Settings does.
- Recall of a bars count on the Photo visual changes the spectrum's bars only (the photo is not reloaded).
- The current scene could not be committed: the edit stays in memory and the next commit retries it (SCN-002).

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-008-R1**: A scene can carry named snapshots, each a name and a set of MOD-001 parameter values; the app captures the seven app-held registry parameters.
- **SCN-008-R2**: Snapshots are stored as an optional top-level `snapshots` array in the scene document; each entry is kept verbatim (unknown fields included); the format version stays 1; a scene without snapshots encodes to the bytes it had before this row; decode → encode is byte-identical.
- **SCN-008-R3**: At most 16 usable snapshots per scene and 64 values per snapshot; the decoder refuses more than 64 entries (`tooMany`); entries past the 16th are kept, not used, and reported.
- **SCN-008-R4**: SCN-012 reports `invalidSnapshot` and `unknownSnapshotParameter` as warnings with their paths; the scene still opens; the repair report lists them.
- **SCN-008-R5**: Save Snapshot captures the current manual values under the next free "Snapshot N" name and commits the current scene; refused at the limit.
- **SCN-008-R6**: Recall writes the snapshot's values through the Settings write path, only values that differ, validated against the registry; it is one undo step labelled "Recall <name>"; it never reloads or touches media, the visual, the preset, the effect chain, text or layers.
- **SCN-008-R7**: A value whose parameter the registry does not know, that the app cannot set, or that the registry rejects is skipped and reported (status, announcement and the row).
- **SCN-008-R8**: Rename (1…64 characters, trimmed, unique case-insensitively) and Delete (confirmed) edit the list and commit the current scene; they are not undo steps.
- **SCN-008-R9**: Settings shows a Snapshots section below the visual options with Save Snapshot and one row per snapshot (name, value count, Recall button); Rename and Delete by swipe and context menu; VoiceOver actions Recall, Rename, Delete; announcements on the library lane; layout works at AX sizes.
- **SCN-008-R10**: The current scene's snapshots survive commit and restore (relaunch) and ride in FILE-005 backups as part of the scene bytes.
- **SCN-008-R11**: The action ID `scene.snapshot.recall` is reserved for a later MIDI/OSC row; no networking, no new settings keys.

### Key Entities

- **Snapshot entry**: the stored object (`name`, `values`, unknown fields kept).
- **Snapshot**: a usable entry: name and `[ParameterID: ParameterValue]`.
- **Recall plan**: the validated writes and the skipped IDs with reasons.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SCN-008-S1**: In the acceptance test, recall restores intensity 0.2 and radius 0.05 exactly, with zero media reloads counted and identical media inputs.
- **SCN-008-S2**: Scenes with snapshots round-trip byte-identically; scenes without them keep their bytes.
- **SCN-008-S3**: 100 % of unknown parameters in the tests are skipped and reported; 100 % of invalid entries are reported and kept.
- **SCN-008-S4**: The 17th snapshot is refused; recall is exactly one undo step.
- **SCN-008-S5**: The UI test (save, change, recall, value label restored) runs in under 30 s on the simulator.

## Assumptions

- Simulator and Mac results are not device evidence; no device-only check is needed for this row.
- Recall does not ease over the transition curve (the live renderer does not run the CMP-014 bus yet).
