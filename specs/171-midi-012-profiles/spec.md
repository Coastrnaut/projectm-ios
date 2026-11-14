# Feature Specification: MIDI-012 MIDI Mapping Profiles

**Feature Branch**: `feature/midi-012` (spec directory `171-midi-012-profiles`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MIDI-012 (MIDI mapping profiles) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Save controller-specific local profiles and export them as files." Acceptance,
verbatim: "Profile round-trip preserves channel, control and destination IDs." Priority P1, effort M, depends on
MIDI-003 (integrated)."

Identifiers carry the roadmap ID: requirements `MIDI-012-R1…`, success criteria `MIDI-012-S1…`, research decisions
`MIDI-012-D1…`, tasks `MIDI-012-T01…`. Other features are cited by their own IDs: MIDI-003/004 (CC mappings, curve
and Invert), MIDI-006 (note triggers), MIDI-007 (scene selection), MIDI-008 (CC buttons, real-time), MIDI-011 (stable
endpoint IDs), FILE-005 (library backup), FILE-011 (local data erase), ACC-004 (announcer lanes).

## Baseline: what exists today (audit of 2026-11-14, branch point `5aaeebe5`)

| Area | Today |
|---|---|
| Mapping store | One global list of text lines in UserDefaults `settings.midi.mappings`: `cc:<ch>:<num>=<id>[;curve=…;invert=1]` (MIDI-003/004), `note:`/`ccbtn:`/`rt:` trigger lines (MIDI-006/008), `pc:` and `note:…=cue.go:` scene lines and `pc:*:*=cue.position` (MIDI-007). Channels are stored 0-15. |
| Unknown lines | Note and scene lists keep lines they own but cannot read. A `cc:` line that cannot be read and a line with an unknown tag are dropped on the next save. |
| Undo | `MIDIMappingCoordinator` keeps one Undo step (CC, note and scene lists) while the MIDI Mappings screen is open. |
| Endpoint identity | MIDI-001/011 `MIDIEndpointID`: the system's unique number, or a name-based fallback that later rows must not persist (ADR-0038 Decision 4). ADR-0038 Decision 8 keeps device identifiers out of the mapping list and its backup, and leaves per-device profiles to MIDI-012. |
| Files | FILE-005 backs up listed UserDefaults keys and named library folders; FILE-011 erases named folders and keys per category. Exports elsewhere use a temporary file and the system file mover; imports use the system file picker. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9).

- Q: What is a profile? → A: A user-named snapshot of the whole stored mapping line list, in order and byte for byte (every line kind, including lines this version cannot read). It is not a second live list: the current mappings stay in `settings.midi.mappings`.
- Q: What makes a profile "controller-specific"? → A: Its name (the user names it after the controller) and an optional local link to one connected input, recorded only as the system's unique number (never a name-based fallback ID and never a name; ADR-0038 Decisions 4 and 8).
- Q: Does a linked profile apply itself when the device connects? → A: No. Applying replaces the user's mappings, so it is always the user's action: while the MIDI Mappings screen is open and a linked input is listed whose profile differs from the current mappings, the Profiles section suggests it with an Apply button. Nothing is announced for the suggestion.
- Q: Where do profiles live, and are they backed up? → A: In one versioned file in the app's Application Support folder (`MIDIProfiles/profiles.json`), at most 32 profiles. The FILE-005 library backup does not carry it (the exported file is the portable form, and the local link is a device identifier ADR-0038 Decision 8 keeps out of backups); the current mapping list stays backed up as today. FILE-011's Settings category erases it.
- Q: What does an exported file contain? → A: A `.pmmidi` JSON document with a format tag, a version, the profile name and the lines, nothing else: never the device link, no dates and no device names.
- Q: Does importing apply? → A: Never. Import validates the file, adds it as a new profile (a repeated name gets " (2)", " (3)" …), keeps lines it cannot read verbatim, and reports what it found and any problems; the user applies it.
- Q: How does Apply interact with Undo? → A: It replaces the stored list in one step, verbatim and in order; one Undo restores the previous list exactly. It is announced on the `.midi` lane.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Save, export, import and apply a profile without losing anything (Priority: P1) — MVP

A performer maps a controller (knobs on channels 1 and 16, pads, a CC button, MIDI Start/Stop, program changes for
scenes), saves it as "Launch Control", exports it to Files, and later imports it on another iPad and applies it. Every
channel, control number and destination is exactly as saved.

**Why this priority**: The row's acceptance.

**Independent Test**: Build a line list with every line kind (CC on channels 1 and 16 with controller 119 and options,
a note trigger with `mode=hold`, `ccbtn:`, `rt:start`/`rt:stop`, `pc:` scene lines, the position mode line and two
unknown lines). Save it as a profile, reload the store, export it, import the file, apply the import. The stored
lines equal the original byte for byte and in order.

**Acceptance Scenarios**:

1. **Given** the mapping list above, **When** it is saved as a profile and the store is reopened, **Then** the profile's lines are byte-identical and in order.
2. **Given** that profile, **When** it is exported and the file is imported, **Then** the imported profile's lines are byte-identical and in order, and the report counts each kind and the two lines this version cannot read.
3. **Given** the imported profile, **When** it is applied, **Then** `settings.midi.mappings` holds exactly those lines in order, the CC, trigger and scene mappings drive as before, and one Undo restores the previous list.

### User Story 2 - Switch between controllers (Priority: P1)

**Acceptance Scenarios**:

1. **Given** two saved profiles, **When** the user taps Apply on the other one, **Then** the mappings change, "Applied MIDI profile <name>." is announced on the `.midi` lane, and Undo returns to the previous mappings.
2. **Given** a profile linked to an input, **When** that input is listed while MIDI Mappings is open and the current mappings differ, **Then** the Profiles section suggests the profile with an Apply button and nothing is applied by itself.

### User Story 3 - Bad files are refused safely (Priority: P1)

**Acceptance Scenarios**:

1. **Given** a file that is not a profile (not JSON, wrong format tag, a newer version, missing name or lines, empty), **When** it is imported, **Then** nothing is added and a plain message says why.
2. **Given** a file over the size limit, or with too many lines, an over-long line or a line with control characters, **When** it is imported, **Then** it is refused without reading further and nothing changes.

### User Story 4 - Manage profiles (Priority: P2)

**Acceptance Scenarios**:

1. **Given** a profile, **When** the user renames or deletes it, **Then** the list and the file change and VoiceOver reads each row as "<name>, <n> mappings".
2. **Given** 32 profiles, **When** the user saves or imports another, **Then** it is refused with "No more profiles fit (32). Delete one first."

### Edge Cases

- Saving with no mappings makes an empty profile; applying it clears the mappings (undoable).
- A name is trimmed, control characters are removed, it is at most 60 characters, and an empty name keeps the old one.
- An unreadable or newer-version profiles file at launch is not overwritten: the section says profiles could not be read, and saving is disabled until the user erases it with FILE-011 or a newer version reads it.
- Applying cancels any learn session in progress and releases held trigger keys whose bindings changed (MIDI-006-R6).
- A linked input with a fallback ID cannot be linked (only system unique numbers).
- Lines the current version cannot read (unknown tags, unreadable `cc:` lines) are kept in the mapping list across later edits, so a profile from a newer version survives a learn.

## Requirements *(mandatory)*

### Functional Requirements

- **MIDI-012-R1**: A profile MUST hold a name, the mapping lines (ordered, verbatim) and optionally a local link (a system unique number).
- **MIDI-012-R2**: Save Current MUST snapshot the stored mapping list verbatim under a new name ("Profile <n>", the lowest free number); Rename and Delete MUST edit the store.
- **MIDI-012-R3**: Profiles MUST be stored in one versioned file under Application Support, written atomically, at most 32 profiles, 512 lines per profile, 256 UTF-8 bytes per line, 60 characters per name; a file the app cannot read MUST never be overwritten.
- **MIDI-012-R4**: Export MUST write a `.pmmidi` JSON document (format tag, version 1, name, lines) through the system file mover; it MUST NOT contain the link, dates or device names.
- **MIDI-012-R5**: Import MUST read at most 128 KB, validate the document (format, version, name, line count, line length, no control characters) and refuse it with a message on any problem; a valid file is added as a new profile (never applied) with a report of line kinds and of lines this version cannot read.
- **MIDI-012-R6**: Apply MUST replace `settings.midi.mappings` with the profile's lines verbatim and in order, reload the CC, trigger and scene mappings, and be one Undo step that restores the previous list exactly; it MUST be announced on the `.midi` lane.
- **MIDI-012-R7**: The mapping list MUST keep lines no list reads (unknown tags, unreadable `cc:` lines) verbatim, after the known lines, across later edits.
- **MIDI-012-R8**: A profile MAY be linked to a listed input with a system unique number; a listed linked input whose profile differs from the current list MUST be suggested, never applied automatically.
- **MIDI-012-R9**: The profiles file MUST be excluded from the FILE-005 library backup and erased by FILE-011's Settings category; no new UserDefaults key.
- **MIDI-012-R10**: The Profiles section MUST sit in the MIDI Mappings screen with Save Current, Apply, Rename, Delete, Export, Import and Link, each with an accessibility label; no animation.
- **MIDI-012-R11**: The profile model, codec and validation MUST be pure Swift and pass on Linux.

### Key Entities

- **Profile**: id, name, lines, optional link (unique number).
- **Profile store file**: version, profiles.
- **Profile document** (`.pmmidi`): format tag, version, name, lines.
- **Import report**: line counts by kind, unread lines, or the refusal reason.

## Privacy review *(Constitution, Privacy)*

- Profiles hold mapping lines (channels, controller numbers, parameter, action and scene IDs) and a user-chosen name.
  The optional link is a system unique number, stays on the device, is never exported and is never backed up. No
  device name is stored. No network API, permission or UserDefaults key is added.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MIDI-012-S1**: The every-kind fixture survives save → store reload → export → import → apply with every line byte-identical and in order (the row's acceptance).
- **MIDI-012-S2**: Every malformed and oversized fixture is refused and changes nothing.
- **MIDI-012-S3**: Apply and one Undo restore the previous list exactly.
- **MIDI-012-S4**: The profiles file is not in a library backup and is removed by the Settings erase.
- **MIDI-012-S5**: A UI test saves a profile and applies another in under 30 s.
- **MIDI-012-S6**: All repository checks pass and the package tests pass on the host (and Linux in CI).

## Assumptions

- The system's unique number of an input stays the same across reconnects (MIDI-001's research), so a link survives a replug.
- Users share profiles as files; no cloud sync is in scope.
- A physical controller check (save, export, import on a second device, apply) is the `{device}` task in the last stage.
