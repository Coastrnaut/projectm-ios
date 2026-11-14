# Feature Specification: MIDI-008 MIDI Transport Mapping

**Feature Branch**: `feature/midi-008` (spec directory `157-midi-008-transport`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MIDI-008 (MIDI transport mapping) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Bind buttons to show play, pause, next cue and blackout." Acceptance, verbatim: "Each
mapped message fires one action despite repeated MIDI packets." Priority P1, effort M, depends on SHOW-001 and
MIDI-003 (both integrated)."

Identifiers carry the roadmap ID: requirements `MIDI-008-R1…`, success criteria `MIDI-008-S1…`, research decisions
`MIDI-008-D1…`, tasks `MIDI-008-T01…`. Other features are cited by their own IDs: MIDI-002 (input and parsers),
MIDI-003 (learn and the mapping list), MIDI-004 (CC options), MIDI-006 (note triggers), MIDI-007 (scene selection),
MOD-006 (threshold triggers), SHOW-001 (cues), OUT-010 (output blackout), ACC-004 (announcer lanes), FR-046/FR-085
(the visualizer's Pause).

## Baseline: what exists today (audit of 2026-11-14, branch point `cec25738`)

| Area | Today |
|---|---|
| Note triggers | MIDI-006 `note:<ch>:<note>=<action>[;mode=hold]` lines for `cue.next`, `cue.previous`, `blackout` (trigger or hold). `MIDINoteRouter` keeps the set of bound keys that are down: a second note on without a note off does nothing, and a trigger fires at most once per binding per batch. Across batches, a duplicated press *and* release (on, off, on, off) fires twice. |
| CC | MIDI-003/004 `cc:<ch>:<num>=<parameter>` lines drive continuous glow parameters only. No CC can trigger an action; a button sending CC 127/0 is not usable as a trigger. |
| Real-time | MIDI-002 parses Start (0xFA), Continue (0xFB) and Stop (0xFC) into `.start`, `.continue`, `.stop` events (the monitor shows them); nothing acts on them. Clock and Active Sensing are counted only. MMC (SysEx) contents are dropped by design (only the byte count is kept). |
| Play / pause | SHOW-001 is a manual cue list: there is no auto-advance or show timeline to play. The app's Pause (FR-046, controls' Pause/Resume, `userPaused`) freezes the picture while capture keeps running, and announces "Visualization paused/resumed" on the `.playback` lane. |
| Next cue, blackout | SHOW-001 `next()`; OUT-010 blackout toggle and MIDI-006's hold; performed by `MIDINoteActionPerformer` (also used by MOD-006). |
| Scenes | MIDI-007 program change / note → `cue.go:<scene>`, debounced on the current scene. |
| Test fakes | `ScriptedMIDIInputProvider` + `MIDIInputCoordinator.drain()`; DEBUG `-uitestFakeMIDI` panel (Send CC, Send Note, Send Program); DEBUG `-uitestShowSeed` (five cues). |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9).

- Q: What do "play" and "pause" control? → A: The visualizer's existing Pause (FR-046: the picture freezes, capture keeps running), because SHOW-001 has no auto-advance or timeline to play. Three actions: Play/Pause (toggle), Play (resume only) and Pause (pause only). They act only while the visualizer is shown; elsewhere they do nothing. A later show timeline can take over the same actions.
- Q: Which messages can trigger a transport action? → A: Three source kinds: a note (MIDI-006's key press), a **CC button** (a controller sending CC values for a button) and a **MIDI real-time** message (Start/Continue, Stop). Every trigger action (Play/Pause, Play, Pause, Next cue, Previous cue, Black out, Black out while held) accepts any of the three; real-time messages are not accepted by the hold row (they have no release).
- Q: How does a CC button press and release? → A: A press is the value crossing upward to 64 or more while the button is released; the button re-arms only when a value below 64 arrives. A repeated 127 without a lower value in between is not a new press.
- Q: Are real-time Start/Stop on by default? → A: No. They act only when the user learns them onto a row (Start and Continue count as one source "Start"). A DAW or drum machine that sends Start/Stop does nothing until mapped.
- Q: What counts as a repeated packet? → A: (1) a second press of a source that is still down (note on without note off, CC 127 without a value below 64); (2) any further press of the same source in the same delivered batch; (3) a press of the same source arriving less than 30 ms after its previous press, even with a release in between (duplicated press-and-release packets). A deliberate second press, with a release in between and at least 30 ms later, fires again. One rule serves notes, CC buttons and real-time.
- Q: Where are the rows? → A: MIDI-006's "Note triggers" section becomes "Transport": the same rows (Next cue, Previous cue, Black out, Black out while held) plus Play/Pause, Play and Pause, each learnable from a note, a CC button or real-time. No rows are duplicated.
- Q: Can one control do two things? → A: No: one action per control. Learning a CC as a button removes its MIDI-003 parameter mapping and learning it for a parameter removes its button mapping (with a "moved from" message), as MIDI-007 already does for notes.
- Q: MMC (MIDI Machine Control SysEx)? → A: Out of scope: MIDI-002 deliberately keeps no SysEx contents (privacy and real-time safety). Recorded for a later row.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: How are the new sources stored? → A: In the same `settings.midi.mappings` list: `ccbtn:<ch 0-15>:<cc 0-119>=<action>[;mode=hold]` and `rt:start=<action>` / `rt:stop=<action>`, after the MIDI-006 `note:` lines. MIDI-003/004 `cc:`, MIDI-006 `note:` and MIDI-007 lines are read and written byte-identically. No new stored key.
- Q: How are the new sources shown and spoken? → A: "CC 20 · Ch 1" (spoken "CC button 20 on channel 1"), "MIDI Start" / "MIDI Stop" (spoken "MIDI Start", "MIDI Stop"); notes as MIDI-006.
- Q: What do the transport actions announce? → A: The app's existing Pause path announces "Visualization paused" / "Visualization resumed" on the `.playback` lane; a Play while playing or Pause while paused changes nothing and announces nothing. Learn prompts and results go on the `.midi` lane. Next cue and blackout keep their own lanes.
- Q: Does a transport action show the controls? → A: No, as MIDI-006's cue steps (the keyboard path): the performer must not reveal the on-screen controls.
- Q: Is the 30 ms window configurable? → A: No. A fixed 30 ms is below any deliberate double press (about 100 ms) and above duplicated packets from USB/BLE bridges (a few ms); it uses the messages' own timestamps, never the time of delivery.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One press, one action (Priority: P1) — MVP

A performer maps a controller's buttons to Next cue and Black out. Some interfaces deliver every message twice. Each press steps once and toggles the blackout once.

**Why this priority**: The row's acceptance.

**Independent Test**: With a fake MIDI source, send the same mapped message twice in several patterns (in one packet list; in two batches 5 ms apart; CC 127 twice with no 0 between) for a note, a CC button and real-time; each press fires exactly once; a deliberate second press after a release fires again.

**Acceptance Scenarios**:

1. **Given** note C4 is mapped to Next cue, **When** two identical note-ons arrive in one packet list, **Then** the show steps once.
2. **Given** the same, **When** note-on/note-off arrive twice, the copies 5 ms apart in two batches, **Then** the show steps once; **When** the key is pressed again 200 ms later, **Then** it steps again.
3. **Given** CC 20 is mapped as a button to Next cue, **When** CC 20 = 127 arrives twice with no lower value between, **Then** the show steps once; after CC 20 = 0 and a new 127, it steps again.
4. **Given** MIDI Start is mapped to Play/Pause, **When** Start arrives twice 5 ms apart, **Then** the pause toggles once.

### User Story 2 - Play and pause from a controller (Priority: P1)

Play/Pause toggles the visualizer's Pause; Play only resumes and Pause only pauses, so a DAW's Start and Stop can drive it.

**Acceptance Scenarios**:

1. **Given** Play/Pause is mapped, **When** pressed twice (released between, far apart), **Then** the picture pauses, then resumes, each announced on the `.playback` lane.
2. **Given** Start → Play and Stop → Pause, **When** Stop arrives while paused, **Then** nothing changes and nothing is announced.

### User Story 3 - Learn a transport source (Priority: P2)

In MIDI Mappings › Transport, Learn on a row accepts the next note press, CC button press (value ≥ 64) or real-time Start/Continue/Stop.

**Acceptance Scenarios**:

1. **Given** listening is on, **When** the user taps Learn on Next cue and presses a CC button (127, then 0), **Then** "Next cue mapped to CC button 20 on channel 1." is shown and announced on the `.midi` lane, the learning press fires nothing, and two later presses step twice.
2. **Given** CC 7 drives a glow parameter, **When** it is learned as a button, **Then** the parameter mapping is removed and the message says it moved.

### Edge Cases

- A CC that is not mapped as a button keeps driving its MIDI-003 parameter exactly as before.
- CC values that hover around 64 (a knob learned by mistake): press at ≥ 64, re-arm only below 64; no chatter on repeated high values.
- Channel mode CCs 120–127 are never buttons.
- Stuck holds: CC 120/123 and System Reset release held notes (MIDI-006); a CC button held for Black out while held is released by the input stopping or the binding changing, as notes.
- Transport actions while the chooser is shown or the app is in the background: nothing happens.
- Unreadable `ccbtn:` / `rt:` lines are kept verbatim, not routed.
- Duplicates of a learning message (the second copy within 30 ms) fire nothing.

## Requirements *(mandatory)*

### Functional Requirements

- **MIDI-008-R1**: The trigger actions MUST include Play/Pause (toggle), Play and Pause, acting on the visualizer's Pause; Play while playing and Pause while paused change nothing; they do nothing unless the visualizer is shown; they never reveal the controls.
- **MIDI-008-R2**: Any trigger action MUST be bindable to a note, a CC button (channel, controller 0–119) or a real-time source (Start, which also covers Continue; Stop); real-time sources are not bindable to the hold row.
- **MIDI-008-R3**: A CC button MUST press when a value ≥ 64 arrives while released and re-arm only when a value < 64 arrives.
- **MIDI-008-R4**: One normalisation rule MUST decide presses for all three source kinds: a press of a source already down, a further press in the same batch, or a press within 30 ms (by message timestamp) of the source's previous press fires nothing; a press after a release and at least 30 ms later fires again.
- **MIDI-008-R5**: Stored as `ccbtn:<ch>:<num>=<action>[;mode=hold]` and `rt:start|stop=<action>` in `settings.midi.mappings`; MIDI-003/004 `cc:`, MIDI-006 `note:` and MIDI-007 lines MUST read and write unchanged; unreadable new lines MUST be kept verbatim.
- **MIDI-008-R6**: One action per control: a source is bound to at most one trigger action, each action to at most one source; a CC is either a button or a parameter control (learning one removes the other, reported as "moved").
- **MIDI-008-R7**: MIDI Mappings MUST show a "Transport" section (MIDI-006's rows plus Play/Pause, Play, Pause) with Learn and Delete; Learn accepts a note press, a CC button press or a real-time message; learning shares MIDI-003's single session, Cancel, timeout, Undo and status line; prompts and results are announced on the `.midi` lane.
- **MIDI-008-R8**: The model MUST build and pass its tests on Linux; no new stored key, permission, usage string or network API.
- **MIDI-008-R9**: A DEBUG UI test MUST learn a CC button for Next cue and press it twice, in under 30 s.

### Key Entities

- **Trigger source**: note (channel, note), CC button (channel, controller) or real-time (Start, Stop).
- **Trigger binding**: a source, an action and a mode (trigger or hold), unknown segments kept.
- **Press filter**: per source, down or up and the time of the last press.

## Privacy review *(Constitution, Privacy)*

- A binding stores the source kind, channel and number (or Start/Stop) and an action only: no device, endpoint, name or time.
- No permission, network ability or new stored key is added.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MIDI-008-S1**: For each source kind (note, CC button, real-time) and each repeat pattern (doubled in one packet list; doubled across two batches 5 ms apart; CC 127 repeated without a 0), each mapped action fires exactly once per press; a deliberate second press after a release fires again (the row's acceptance).
- **MIDI-008-S2**: Play/Pause toggles the pause state; Play and Pause are idempotent.
- **MIDI-008-S3**: CC hysteresis: no second press without a value below 64.
- **MIDI-008-S4**: Stored lines round-trip; MIDI-003/004/006/007 lines are unchanged in a mixed list; unknown lines are kept.
- **MIDI-008-S5**: A UI test learns a CC button for Next cue and presses it twice in under 30 s.
- **MIDI-008-S6**: All repository checks pass and the package tests pass on the host (and Linux in CI).

## Assumptions

- The trigger list keeps MIDI-006's capacity of 64 bindings across all source kinds.
- 30 ms is below any deliberate re-press and above packet duplication by interfaces and bridges.
- Every message from CoreMIDI carries a timestamp (the input substitutes the arrival time for a zero timestamp); a message built without one (timestamp 0) is judged by the down state and the same-batch rule only.
- A physical controller check is the `{device}` task in the last stage; simulator results are never device evidence.
