# Feature Specification: SHOW-012 Cue Annotations

**Feature Branch**: `feature/show-012` (spec directory `285-show-012-cue-annotations`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: Roadmap row SHOW-012 (P2, size S, depends on SHOW-001, integrated). Observable behavior, verbatim: "Attach
private operator notes to cues." Acceptance, verbatim: "Notes survive export and do not appear in live output."

Identifiers carry the roadmap ID: requirements `SHOW-012-R1…`, success criteria `SHOW-012-S1…`, tasks `SHOW-012-T01…`,
research decisions `SHOW-012-D1…`. Other features are cited by their own IDs: SHOW-001 (show and cues), SHOW-002 (dwell),
SHOW-004 (transition override), SHOW-005 (skip), SHOW-007 (timeline transport), SHOW-015 / SCN-015 (performance lock),
SCN-003 (Duplicate Scene), FILE-004 (scene import), FILE-005 (library backup and restore), OUT-001 (external display),
OUT-005 (guides), UIX-013 (HUD), OSC-005 (OSC send), ACC-004 (announcer lanes), ACC-011 (captions), REC (recordings),
FRAME (Save Frame), OFFLINE (offline export).

## Baseline (audit of 2026-11-15, commit `11bb4887`)

| Area | Today | SHOW-012 |
|---|---|---|
| Cue model (`ShowCue`) | ID, scene ID, label, transition, dwell, override, skip | Adds an optional note |
| Show file (`show.json`, version 1) | Optional cue fields written only when set, read leniently with counted warnings, no version bump | Adds optional cue `note` the same way |
| FILE-005 backup | Carries the show as canonical bytes (decode → encode); an exact restore writes them back | Notes ride along with no backup change |
| FILE-005 merge restore / FILE-004 scene import / SCN-014 scene packs | Carry scenes, never cue metadata (transitions, dwells, skips) | Unchanged: scenes have no notes |
| Show editor rows | Label, scene, transition, override, dwell, skipped; More… dialog, context menu, VoiceOver actions; edits hidden while locked | Adds a note line, a Note… action and a note editor sheet |
| Live output (external display, recordings, Save Frame, offline export, HUD, transport readout, OSC send, captions, cue announcements) | Built from the scene document, the cue label and position, never from other cue fields | Must never carry the note |

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: What is a note? → A: Optional plain text per cue, at most 500 characters (as the user sees them). Line breaks are
  kept (normalized to one line feed); every other control character is removed; leading and trailing spaces and blank
  lines are trimmed; empty text means no note. Rejected: rich text (nothing to render it in output anyway; harder to keep
  private), a show-level note (the row asks for cue notes).
- Q: Where is it stored? → A: In the show document, on the cue, as an optional `note` field written only when the cue has
  one, so shows without notes keep their exact bytes (no version bump, as SHOW-002/004/005 did). Rejected: a separate
  notes file (would need its own backup path and could drift from the cue IDs).
- Q: Which exports carry it? → A: Every path that carries the show: the stored show, the FILE-005 backup (archive and
  folder) and its exact restore. Scene packs and scene imports carry scenes, not cues, so they carry no notes, exactly as
  they carry no transitions or dwells today. Rejected: adding notes to scene packs (a note belongs to a cue, and several
  cues can share a scene).
- Q: Where does a note show? → A: Only in operator UI on the device: the cue's row in Settings › Show (a note line with a
  preview) and the note editor sheet. Not in the HUD: the HUD is device-only today, but a "next cue note" line is not
  needed for the acceptance and every new HUD line widens what could leak if the HUD's isolation ever regressed.
- Q: Does VoiceOver read the note? → A: Yes, on the cue's row in the editor (", note <text>"), because the editor is the
  operator's own screen and a blind operator must be able to read their notes. A note is never posted as an announcement
  or caption (those can be heard by the room through a shared speaker and are logged by status events).
- Q: May a note be edited while the performance lock is on? → A: No. A note change is a cue edit, refused like every
  other cue edit (SCN-015-R4, SHOW-015); the Note… action is hidden while locked. The note line stays visible (reading is
  not an edit).
- Q: Does Duplicate Scene copy the note? → A: Yes, like the cue's transition, dwell, override and skip flag (SCN-003).
- Q: A stored note that breaks the rules (not text, too long, control characters)? → A: Read leniently: text is
  normalized and cut to 500 characters (counted warning "shortened notes"); anything that is not text is dropped (counted
  warning "dropped notes"). The show is never refused for a note.

### Session 2026-11-15 (speckit-clarify)

- Q: What happens when the operator types more than 500 characters in the note editor? → A: The text stays as typed, the
  counter shows "501 / 500" in the warning style and Save is disabled until it fits; nothing is cut silently. Rejected:
  cutting while typing (a paste would lose its end without notice).
- Q: Does SHOW-006 cue rehearsal or the scene switcher show the note? → A: No. Notes appear only in Settings › Show (row
  and editor sheet) for this row; other operator surfaces can adopt them later. Fewer surfaces, less to keep private.
- Q: How much of the note does the row show? → A: An icon (note.text) and the first line, at most 60 characters,
  followed by "…" when longer; the full text is in the editor and in VoiceOver's value.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Write a private note on a cue (Priority: P1)

An operator preparing a show opens Settings › Show, picks a cue's Note… action, types "Wait for the drummer's count-in",
and saves. The cue's row now shows a note indicator with the start of the text.

**Why this priority**: It is the feature.

**Independent Test**: Add a note to a cue in the editor and see the indicator; relaunch and see it again.

**Acceptance Scenarios**:

1. **Given** a show with a cue, **When** the operator saves a note on it, **Then** the row shows a note indicator with a
   preview and the show is saved at once.
2. **Given** a cue with a note, **When** the operator clears the text and saves, **Then** the note is removed.
3. **Given** the performance lock is on, **When** the operator looks at the cue, **Then** the note line is shown but no
   Note… action is offered, and a note change that still reaches the app is refused with the lock message.

### User Story 2 - Notes survive export (Priority: P1)

The operator backs up the library and restores it on another device; every cue keeps its note exactly.

**Acceptance Scenarios**:

1. **Given** a show with notes, **When** it is saved and loaded, or backed up and restored exactly, **Then** each note is
   unchanged, character for character.
2. **Given** a show file from before this feature, **When** it is loaded, **Then** every cue has no note and the file's
   bytes are unchanged when saved again.

### User Story 3 - Notes never reach the audience (Priority: P1)

During the show the operator steps to a cue with a note. The external display, recordings, saved frames, the HUD,
the transport readout, captions, cue announcements and OSC send show or carry exactly what they did without the note.

**Acceptance Scenarios**:

1. **Given** a cue whose note is a distinctive string, **When** the cue is applied, **Then** that string appears in none
   of: the external display's view tree, the HUD texts, the transport readout, the show status text, cue announcements,
   the notice, the scene data applied to the output (and so any text layer of a recording or saved frame), or the OSC
   send payload.

### Edge Cases

- A 501-character note is refused in the editor (the Save button is disabled with a counter) and cut to 500 on load.
- A note with only spaces and line breaks is no note.
- Tabs, NUL and other control characters are removed; emoji and combining marks count as one character each.
- Removing a cue removes its note; moving a cue keeps it.

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-012-R1**: Each cue MAY carry one note: plain text of 1…500 characters after normalization (control characters
  other than line feed removed, CR LF / CR / U+2028 / U+2029 turned into line feeds, trimmed).
- **SHOW-012-R2**: The note MUST be stored in the show document as an optional cue field written only when set; a show
  without notes MUST keep its exact bytes; no format version change.
- **SHOW-012-R3**: Reading MUST be lenient: a text note is normalized and cut to 500 characters (counted warning), a
  non-text value is dropped (counted warning); the show is never refused because of a note.
- **SHOW-012-R4**: The note MUST survive save/load, the FILE-005 backup and its exact restore byte for byte.
- **SHOW-012-R5**: The show editor MUST show a note line (indicator and the first line, at most 60 characters) on a cue with a note, and
  offer Note… (Add Note… / Edit Note…) in the cue's More… dialog, context menu and VoiceOver actions, opening a note editor with a character count
  and Save/Cancel.
- **SHOW-012-R6**: Saving a note MUST save the show at once and MUST NOT apply a scene, move the position or restart a
  countdown.
- **SHOW-012-R7**: While the performance lock is on, note edits MUST be refused (lock message) and the Note… action
  hidden; the note line stays.
- **SHOW-012-R8**: VoiceOver MUST read the note as part of the cue row's value in the editor; the note MUST NOT be posted
  as an announcement or caption.
- **SHOW-012-R9**: The note MUST NOT reach live output: external display, recordings, Save Frame, offline export, HUD,
  transport readout, show status text, captions, announcements, OSC send, diagnostics and performance reports.
- **SHOW-012-R10**: Duplicate Scene MUST copy the cue's note to the new cue.
- **SHOW-012-R11**: A repository check MUST fail when an output, diagnostics or report source names the note.

### Key Entities

- **Cue note**: optional normalized text on a cue (≤ 500 characters), keyed by the cue, stored in the show document.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHOW-012-S1**: 100% of notes in a test show come back identical after save/load and after backup and exact restore.
- **SHOW-012-S2**: A distinctive note string occurs 0 times in every live-output channel listed in R9 after its cue is
  applied.
- **SHOW-012-S3**: An operator adds a note to a cue in under 30 seconds (UI test: open the action, type, save, see the
  indicator).
- **SHOW-012-S4**: 0 note edits succeed while the lock is on.

## Assumptions

- No new settings or UserDefaults keys: notes live in the show document only.
- Merge restore, scene import and scene packs keep carrying scenes only (no cue metadata), unchanged.
- Simulator results are never device evidence; the device check is a `{device}` task.
