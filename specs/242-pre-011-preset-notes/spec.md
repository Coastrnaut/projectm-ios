# Feature Specification: PRE-011 Preset Notes

**Feature Branch**: `feature/pre-011` (spec directory `242-pre-011-preset-notes`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement PRE-011 (Preset notes) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Store private free-text notes linked to stable preset IDs."
Acceptance, verbatim: "Notes survive relaunch and never appear in exported diagnostics." P2, effort S."

Identifiers in this feature carry the roadmap ID: requirements `PRE-011-R1…`, success criteria `PRE-011-S1…`,
research decisions `PRE-011-D1…`, tasks `PRE-011-T01…`. Other features are cited by their own IDs: PRE-003
(tags), PRE-008 (smart collections), PRE-012 (user presets), PRE-016 (overrides), PRE-018 (integrity scanner),
FILE-005 (library backup), FILE-007 (document schemas), FILE-011 (erase), PERF-012 (performance report).

## Baseline: what exists today (audit of 2026-11-14, commit `5d6b34da`)

| Question | Today |
|---|---|
| Per-preset user data | PRE-003 `PresetTagStore` (`PresetCollections/tags.json`) and PRE-016 `PresetOverrideStore` (`overrides.json`): maps keyed by the stable preset ID, schema version 1, newer version = unavailable (never written), unreadable = set aside, every change saved atomically before it is shown. PRE-008 `smart-collections.json` adds a migration table. |
| Free text about a preset | **None.** A user can tag a preset but cannot write anything longer about it. |
| Preset detail | The browser row's touch-and-hold menu and VoiceOver actions open per-preset sheets: Tags… (PRE-003), Adjust Parameters… (PRE-016). |
| Backup and erase | FILE-005 backs up `tags.json`, `overrides.json`, `smart-collections.json` as separate records and merges them on restore; FILE-011's collections erase removes the whole `PresetCollections` folder and counts entries. |
| Integrity | PRE-018 reports dangling IDs in favorites, tags, adjustments, collections and recents. |
| Diagnostics exports | PERF-012 performance report (app; gathers only counters), CaptureLab's `DiagnosticsExporter` snapshot (separate harness app; no preset data), `DiagnosticsLog` os_log/signposts, the DEBUG/automation-only `AutomationRunner` reports. None reads a preset store. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where are notes stored? → A: In their own versioned file `PresetCollections/notes.json` (schema 1), a map from stable preset ID to note text, beside `tags.json` and `overrides.json`, with the same rules: migration table keyed by version (as PRE-008), a newer version leaves notes unavailable and the file untouched, an unreadable file is renamed aside, every change is saved atomically before it is shown.
- Q: What is a valid note? → A: Text trimmed of leading and trailing whitespace and newlines, at most 2,000 characters (grapheme clusters, as the character count shows); saving an empty note removes it; a longer note is refused with a message (the editor stops at the limit). At most 20,000 presets may have notes (as PRE-016).
- Q: Do notes appear in diagnostics? → A: Never. No diagnostics, performance report, log, signpost or automation report reads the notes store; a repository check enforces that no diagnostics source names it, and tests export each diagnostics document with distinctive marker notes present and assert the markers are absent.
- Q: Do notes travel in the library backup? → A: Yes: they are the user's own data and the backup is a local file the user saves. FILE-005 carries `collections/notes.json`; restore merges per preset ID (new note added, identical kept, a clash follows the restore choice: Replace takes the backup's, Keep both and Skip keep the device's). FILE-011's collections erase removes and counts them.
- Q: Do notes travel in shared exports (preset `.milk` export, scene and show packs, OSC, MIDI)? → A: No. Those are made to be shared with other people or devices; notes are private.
- Q: Does search include notes? → A: Yes: browser search also matches presets whose note contains the text (folded, as tags, PRE-003-R9). It is local, in-memory and the user's own text.
- Q: What happens to the note of a removed preset? → A: Removing one of the user's presets removes its note (as tags and adjustments). A note naming an ID the library no longer lists is kept but hidden, and PRE-018 reports it as a dangling reference ("Notes", fix "Remove Note").

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Write a note about a preset (Priority: P1) — MVP

I touch and hold a preset, choose Note…, type "Great for the wedding intro — slow build", and tap Save. The row
now shows a note symbol; reopening Note… shows my text; after I quit and relaunch the app it is still there.

**Why this priority**: It is the row's observable behavior and half of its acceptance.

**Independent Test**: A package test saves notes in one store and reads them back with a new store on the same
folder (a simulated relaunch); a UI test adds a note and sees the row's indicator.

**Acceptance Scenarios**:

1. **Given** a preset without a note, **When** I write and save a note, **Then** the row shows a note indicator and VoiceOver says "has note".
2. **Given** a saved note, **When** the app relaunches, **Then** the note is unchanged.
3. **Given** a note, **When** I clear its text and save, **Then** the note is removed and the indicator disappears.
4. **Given** the editor, **When** I type, **Then** the character count shows "n of 2,000" and text past the limit is not accepted.

### User Story 2 - Notes stay private (Priority: P1)

**Why this priority**: It is the other half of the acceptance ("never appear in exported diagnostics").

**Independent Test**: With notes containing distinctive marker strings saved through the app's store, the
PERF-012 report and a diagnostics snapshot encoded through `DiagnosticsExporter` are generated and contain none of
the markers; the compliance check refuses any diagnostics source that names the notes store.

**Acceptance Scenarios**:

1. **Given** notes with marker text, **When** I export the performance report, **Then** the file contains no marker.
2. **Given** notes, **When** any diagnostics export is generated, **Then** no note text, and no preset ID taken from the notes, is in it.

### User Story 3 - Notes are kept safely (Priority: P2)

**Independent Test**: Store tests (newer version unavailable, unreadable set aside, injected migration, failed save
changes nothing); a library backup round trip restores the notes; erase removes them; PRE-018 reports a dangling note.

**Acceptance Scenarios**:

1. **Given** notes, **When** I back up the library and restore it on a fresh install, **Then** the notes are back.
2. **Given** a notes file from a newer app version, **When** the app opens, **Then** notes are read-only unavailable and the file is untouched.

### Edge Cases

- A note for a locked preset can be written and read (locking is about playing, not about the user's own text).
- A note for a preset whose pack is removed is kept (hidden); PRE-018 reports it; re-adding the pack shows it again.
- Whitespace-only text counts as empty: saving removes the note.
- Text with emoji and combining marks counts by visible characters.
- A save that fails (disk full) shows "Your note could not be saved." and keeps the editor open with the text.

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-011-R1**: A note MUST be linked to a stable preset ID (the IDs used by favorites, tags and collections), hold trimmed text of 1 to 2,000 characters, and at most one note per preset; saving empty text MUST remove the note.
- **PRE-011-R2**: Notes MUST be saved in `PresetCollections/notes.json`: schema version 1, a migration table keyed by version, a FILE-007 schema check before reading, a newer version leaving notes unavailable and the file untouched, an unreadable file renamed aside, every change saved atomically before it is shown (a failed save changes nothing and reports why). Invalid entries in a readable file are dropped and counted.
- **PRE-011-R3**: The browser row MUST offer "Note…" (touch-and-hold menu) and a "Note" VoiceOver action, opening an editor with an accessible multi-line text field, a live character count "n of 2,000", Save, Cancel and (when a note exists) Delete Note.
- **PRE-011-R4**: A row whose preset has a note MUST show a note symbol, and its VoiceOver label MUST end with ", has note" (the note text itself is not read in the row label).
- **PRE-011-R5**: Browser search MUST also match presets whose note contains the search text (case and accent folded).
- **PRE-011-R6**: Notes MUST never be read by, or appear in, any diagnostics output: the PERF-012 performance report, the CaptureLab diagnostics export, `DiagnosticsLog` logs and signposts, and automation reports. Notes MUST NOT be written to UserDefaults, logs or shared exports (preset export, scene and show packs, OSC, MIDI).
- **PRE-011-R7**: FILE-005 MUST back up notes as `collections/notes.json` and merge them on restore per preset ID by the restore choice; FILE-011's collections erase MUST remove and count them.
- **PRE-011-R8**: Removing a user preset MUST remove its note; PRE-018 MUST report a note whose preset ID the library does not list as a dangling reference, with the safe fix "Remove Note".
- **PRE-011-R9**: The note model, file and store MUST be Foundation-only Swift in `PresetLibrary` that builds on Linux.

### Key Entities

- **PresetNoteMap**: preset ID → note text, with the validation rules.
- **PresetNotesFile** / **PresetNoteStore**: the versioned document and its transactional store.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-011-S1**: A note saved by one store is read unchanged by a new store on the same folder (simulated relaunch); trimming, the 2,000-character limit and empty-removes behave as specified (package test).
- **PRE-011-S2**: With marker notes saved, the PERF-012 report and an encoded diagnostics snapshot contain no marker (app unit test); the compliance check fails on a diagnostics source that names the notes store (script test).
- **PRE-011-S3**: Backup round trip restores notes; restore merges by choice; erase removes them (LibraryBackup test).
- **PRE-011-S4**: In the app on a simulator, adding a note shows the row indicator (UI test under 30 s).
- **PRE-011-S5**: PRE-018 reports a dangling note and Fix All Safe removes it (package and app tests).

## Assumptions

- No new UserDefaults key: notes live only in `notes.json`.
- Notes are plain text (no formatting, links or attachments).
- The editor is a sheet from the browser row, like Tags… and Adjust Parameters…; there is no separate preset detail screen.
