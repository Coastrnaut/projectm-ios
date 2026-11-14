# Feature Specification: MIDI-007 MIDI Scene Selection

**Feature Branch**: `feature/midi-007` (spec directory `147-midi-007-scene-selection`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (MIDI-007-T01-T14 verified on the Mac with the scripted MIDI system; device task T15 `{device}` open)

**Input**: User description: "Implement MIDI-007 (MIDI scene selection) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Recall scenes using configurable program-change or note mapping." Acceptance,
verbatim: "Program change selects correct scene without changing stored mappings." Priority P1, effort M, depends on
MIDI-006 and SCN-001 (both integrated)."

Identifiers carry the roadmap ID: requirements `MIDI-007-R1…`, success criteria `MIDI-007-S1…`, research
decisions `MIDI-007-D1…`, tasks `MIDI-007-T01…`. Other features are cited by their own IDs: MIDI-002 (input and
parsers), MIDI-003 (learn and the mapping list), MIDI-004 (CC options), MIDI-006 (note triggers), SHOW-001 (cues,
Go to Cue), SCN-001 (scene documents), SCN-004 (scene folders), ACC-004 (announcer lanes), MIDI-008 (transport,
later).

## Baseline: what exists today (audit of 2026-11-14, branch point `4bad23aa`)

| Area | Today |
|---|---|
| Program change | MIDI-002 parses it (`MIDIEvent` kind `.programChange`, number = program 0–127) and the MIDI Monitor shows "Program 5"; nothing acts on it. |
| Notes | MIDI-006 `note:<ch>:<note>=<action>[;mode=hold]` lines (`cue.next`, `cue.previous`, `blackout`), `MIDINoteRouter`, `MIDINoteActionPerformer`. A `note:` line with an unknown action (for example `cue.go:<id>`) is kept verbatim but drives nothing. |
| Mappings store | One `[String]` under `settings.midi.mappings` (MIDI-003 `cc:` lines, then MIDI-006 `note:` lines); covered by FILE-005 backup and the Settings erase. |
| Scenes | SHOW-001 cues reference SCN-001 scenes by scene ID; `ShowCoordinator.goToScene(_:)` is SCN-004's "Go to Cue" for a scene (its first cue). `list.activeSceneID` is the current cue's scene. |
| Applying a scene | `AppCoordinator.applyShowScene` sets the look through Settings' setters; it never reads or writes `settings.midi.mappings`. |
| Learn | `MIDILearnSession<Target>` with an eligibility rule; one learn session at a time in `MIDIMappingCoordinator`. |
| Test fakes | `ScriptedMIDIInputProvider` + `MIDIInputCoordinator.drain()`; DEBUG `-uitestFakeMIDI` panel (Send CC, Send Note); DEBUG `-uitestShowSeed` (five cues over five scenes). |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9).

- Q: How is a program change mapped to a scene? → A: A scene mapping binds one channel and program to one scene ID, stored as `pc:<ch 0-15>:<program 0-127>=cue.go:<sceneID>` in `settings.midi.mappings`.
- Q: Can a note select a scene too? → A: Yes: `note:<ch>:<note>=cue.go:<sceneID>`, the line MIDI-006 already kept verbatim, now readable. A scene note fires on the key's down edge (velocity > 0); its release does nothing.
- Q: Is there a "program number = cue position" mode, and is it on by default? → A: Yes, optional and **off by default**: when on, program n on the chosen channel (or on any channel) selects the show's cue n + 1 (program 0 → cue 1). Off by default because a controller that sends program changes for its own patches would otherwise move the show unasked. Stored as one line `pc:<ch|*>:*=cue.position`; explicit program mappings win over the mode.
- Q: Does selecting a scene change stored mappings? → A: Never. Applying a scene (by MIDI or otherwise) MUST leave `settings.midi.mappings` byte-identical, even if the scene carries MIDI-related state (SCN-001 bindings); only learning, deleting, Undo and the mode picker write it.
- Q: What if the mapped scene is not in the show? → A: Nothing changes; "Scene not found." is announced on the `.midi` lane. With the position mode, a program past the last cue announces "Cue n not found." and does nothing.
- Q: How is a scene assigned? → A: "Assign MIDI…" on a cue (context menu, a leading swipe action and a VoiceOver action) in Settings → Show opens a sheet that learns the next program change or note on (velocity > 0) for that cue's scene, with the shared status line, Cancel and 30 s timeout.
- Q: Repeated program change? → A: A trigger for the scene that is already current (the active cue's scene) does nothing (no re-apply, no announcement). The same holds for a scene note and for the position mode (the active cue).
- Q: Is bank select (CC 0/32) in scope? → A: No. Programs are matched on channel and number only; bank select is ignored (it remains a normal CC for MIDI-003 learn, which only offers the glow parameters). A later row can add banks without changing the stored form (a `;bank=` segment).

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: How is a scene mapping shown and spoken? → A: Programs as the MIDI Monitor shows them, 0–127: "Program 5 · Ch 1", spoken "program 5 on channel 1"; notes as MIDI-006 ("Note C4 · Ch 1", "note C4 on channel 1"). The learn result reads "<scene name> mapped to program 5 on channel 1."
- Q: What happens to a scene mapping when its scene leaves the show? → A: It is kept (the row reads "Scene not found" in place of the name, and a trigger announces "Scene not found."), so re-adding the scene or restoring a backup brings it back; the user deletes it by hand. Nothing is removed automatically.
- Q: Which edits get an Undo entry? → A: Learning and deleting a scene mapping share MIDI-003's one-step Undo (Undo restores the CC, note and scene lists together). The "Program number selects cue" picker saves at once with no Undo entry, as MIDI-004's curve picker.
- Q: Where is "Assign MIDI…" offered? → A: On each cue in Settings → Show (context menu, a leading "MIDI" swipe action and a VoiceOver action "Assign MIDI"). The Scene Folders view is not changed (its rows already offer Go to Cue; one entry point keeps the learn sheet in one place).
- Q: Do scene triggers keep working while a learn session runs? → A: Yes: every message except the one a learn session consumes is routed as usual, so learning never blocks a show; the learning message itself selects nothing and fires no MIDI-006 trigger.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A program change recalls a scene (Priority: P1) — MVP

A performer's foot controller sends program changes. After mapping program 5 on channel 1 to the "Drop" scene,
pressing that patch shows the Drop cue, and the saved mappings are untouched.

**Why this priority**: The row's acceptance.

**Independent Test**: With a fake MIDI source, map PC 5 / channel 1 to scene X, send PC 5, and check the current cue
shows X and the stored mappings are byte-identical before and after.

**Acceptance Scenarios**:

1. **Given** PC 5 on channel 1 is mapped to scene X, **When** PC 5 arrives on channel 1, **Then** X's first cue becomes current and X is applied, and `settings.midi.mappings` is byte-identical.
2. **Given** the same mapping, **When** PC 5 arrives on channel 2, **Then** nothing changes.
3. **Given** X is already current, **When** PC 5 arrives again, **Then** nothing is re-applied.
4. **Given** a mapping to a scene no cue shows, **When** its program arrives, **Then** nothing changes and "Scene not found." is announced on the `.midi` lane.

### User Story 2 - A pad recalls a scene (Priority: P1)

A note mapped to a scene selects it on key down, the same way, without changing stored mappings.

**Independent Test**: Map note 60 / channel 1 to scene Y, send note on 60, check Y is current and the mappings are byte-identical.

**Acceptance Scenarios**:

1. **Given** note C4 on channel 1 is mapped to scene Y, **When** note on (velocity > 0) arrives, **Then** Y becomes current; the note off does nothing.
2. **Given** a MIDI-006 trigger on another note, **When** both notes arrive, **Then** each does its own action.

### User Story 3 - Program number selects cue position (Priority: P2)

A user with a fixed program list turns on "Program number selects cue" (any channel or one channel), and program n selects cue n + 1.

**Acceptance Scenarios**:

1. **Given** the mode on for channel 1 and five cues, **When** PC 2 arrives on channel 1, **Then** cue 3 becomes current; on channel 2 nothing happens.
2. **Given** the mode on, **When** PC 9 arrives, **Then** "Cue 10 not found." is announced and nothing changes.
3. **Given** the mode on and PC 2 explicitly mapped to scene X, **When** PC 2 arrives, **Then** X is selected (the explicit mapping wins).

### User Story 4 - Assign MIDI to a scene (Priority: P2)

In Settings → Show, "Assign MIDI…" on a cue learns the next program change or note for its scene; MIDI Mappings lists the scene mappings with Delete.

**Acceptance Scenarios**:

1. **Given** listening is on, **When** the user picks "Assign MIDI…" on cue 3 and sends PC 5, **Then** "Drop mapped to program 5 on channel 1." is shown and announced, and PC 5 then selects Drop.
2. **Given** a note already drives a MIDI-006 trigger, **When** it is assigned to a scene, **Then** it moves to the scene (one action per note).

### Edge Cases

- A program or note on a channel other than the mapping's: ignored.
- Several scene triggers in one delivered batch: only the newest acts (the input drains at most 30 times a second).
- A scene shown by several cues: its first cue is selected (SCN-004 Go to Cue).
- A scene whose file cannot be read but whose cue exists: SHOW-001's step path handles it (repair report or notice), as for Go to Cue.
- Learning a key or program already mapped to another scene: it moves (one scene per key; one key per scene).
- Unreadable `pc:` or `note:…=cue.go:` lines: kept verbatim, not shown, not routed.
- MIDI-003/004 `cc:` lines and MIDI-006 `note:` trigger lines: read and written exactly as before.
- At most 128 scene mappings (the full MIDI address space for programs on one channel; see Assumptions).
- A scene removed from the show: its mapping is kept and its row reads "Scene not found".
- MIDI listening off: "Assign MIDI…" shows the MIDI-003 off text and cannot learn.

## Requirements *(mandatory)*

### Functional Requirements

- **MIDI-007-R1**: A scene mapping MUST bind one channel and program (program change) or one channel and note (note on) to one scene ID; stored as `pc:<ch>:<program>=cue.go:<sceneID>` or `note:<ch>:<note>=cue.go:<sceneID>` in `settings.midi.mappings`.
- **MIDI-007-R2**: A mapped program change, or a mapped note's down edge (velocity > 0), MUST select the scene's first cue through SHOW-001's Go to Cue path; channel and number must both match.
- **MIDI-007-R3**: Selecting a scene MUST NOT change `settings.midi.mappings` (byte-identical), whatever the scene contains.
- **MIDI-007-R4**: A trigger for a scene no cue shows MUST change nothing and announce "Scene not found." on the `.midi` lane.
- **MIDI-007-R5**: A trigger for the scene (or, in position mode, the cue) that is already current MUST do nothing.
- **MIDI-007-R6**: An optional "Program number selects cue" mode, off by default, MUST map program n to cue n + 1 on any channel or one chosen channel; explicit program mappings win; a program past the last cue announces "Cue n not found." and does nothing. Stored as one `pc:<ch|*>:*=cue.position` line.
- **MIDI-007-R7**: Reading and writing MUST keep MIDI-003/004 `cc:` lines and MIDI-006 trigger `note:` lines unchanged, and keep unreadable `pc:` and `note:…=cue.go:` lines verbatim.
- **MIDI-007-R8**: "Assign MIDI…" on a cue in Settings → Show MUST learn the next program change or note on (velocity > 0) for its scene, sharing MIDI-003's single learn session, Cancel, 30 s timeout and status line; the learning message itself selects nothing. A key or program moves from any other scene or MIDI-006 trigger; a scene keeps one key.
- **MIDI-007-R9**: MIDI Mappings MUST show a "Scene triggers" section: one row per scene mapping (scene name or "Scene not found", "Program 5 · Ch 1" or "Note C4 · Ch 1", Delete), and the "Program number selects cue" picker (Off, Any channel, Channel 1–16). Deleting and learning share MIDI-003's one-step Undo; the picker saves at once with no Undo entry.
- **MIDI-007-R10**: Learn start, result, timeout and "not found" messages MUST be announced on the `.midi` lane; a selected cue announces through SHOW-001's `.cue` lane only.
- **MIDI-007-R11**: The model MUST build and pass its tests on Linux; no new stored key, permission, usage string or network API.
- **MIDI-007-R12**: A DEBUG UI test MUST assign a program to a scene and trigger it with the stand-in MIDI input in under 30 s.

### Key Entities

- **Scene mapping**: trigger kind (program change or note), channel, number, scene ID, unknown segments kept.
- **Program cue mode**: off, any channel, or one channel.
- **Scene command**: select a scene ID, or select a cue position.

## Privacy review *(Constitution, Privacy)*

- A scene mapping stores channel, program or note number and a scene ID (a local UUID) only: no device, endpoint, name or time.
- No permission, network ability or new stored key is added.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MIDI-007-S1**: With a fake MIDI source, PC 5 on channel 1 mapped to scene X makes X current and applied, and the stored mappings are byte-identical before and after; the same for a note mapping (the row's acceptance).
- **MIDI-007-S2**: Another channel selects nothing; a repeated trigger for the current scene re-applies nothing; a missing scene changes nothing and is announced.
- **MIDI-007-S3**: Position mode selects cue n + 1 on the chosen channel only; explicit mappings win; past the end is announced.
- **MIDI-007-S4**: Stored lines round-trip; MIDI-003/004/006 lines are unchanged in a mixed list; unknown lines are kept.
- **MIDI-007-S5**: A UI test assigns a program to a scene and triggers it in under 30 s.
- **MIDI-007-S6**: All repository checks pass and the package tests pass on the host (and Linux in CI).

## Assumptions

- Scene IDs are SCN-001 IDs (UUID text); a readable ID is 1–64 characters of letters, digits, `-`, `_` and `.`.
- The scene mapping list holds at most 128 mappings (one channel's programs; a show rarely needs more MIDI-addressed scenes). Learning past the limit says "No more mappings fit" as MIDI-003.
- A physical controller check is the `{device}` task in the last stage; simulator results are never device evidence.
