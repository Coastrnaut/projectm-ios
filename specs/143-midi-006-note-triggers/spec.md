# Feature Specification: MIDI-006 MIDI Note Triggers

**Feature Branch**: `feature/midi-006` (spec directory `143-midi-006-note-triggers`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (MIDI-006-T01-T15 verified on the Mac with the scripted MIDI system; device task T16 `{device}` open)

**Input**: User description: "Implement MIDI-006 (MIDI note triggers) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Map note-on and note-off to scene and effect triggers." Acceptance,
verbatim: "Velocity zero note-on is treated as note-off consistently." Priority P1, effort M, depends on
MIDI-003 (integrated). Verification: unit tests with fake MIDI; a physical controller in the last stage."

Identifiers carry the roadmap ID: requirements `MIDI-006-R1…`, success criteria `MIDI-006-S1…`, research
decisions `MIDI-006-D1…`, tasks `MIDI-006-T01…`. Other features are cited by their own IDs: MIDI-002 (input
and parsers), MIDI-003 (learn and the mapping list), MIDI-004 (CC options), SHOW-001 (cues), OUT-010 /
SHOW-014 (output blackout), ACC-004 (announcer), MIDI-007 (scene selection, later), MIDI-008 (transport
mapping, later).

## Baseline: what exists today (audit of 2026-11-14, branch point `09621948`)

The row's gap status is "Gap candidate". The audit confirms a gap: notes are parsed and shown in the MIDI
Monitor but drive nothing.

| Area | Today |
|---|---|
| Parsing | MIDI-002 `MIDIByteStreamParser` (bytes, running status) and `MIDIUMPDecoder` (UMP MIDI 1.0 words) both build channel messages through `MIDIEvent.channelVoice`, which already turns a note on with velocity 0 into a note off with value 0. Running status is kept across channel messages. |
| Keys | `MIDIEvent.controlKey` gives a note on and its note off the same key (kind `.noteOn`, channel, number). |
| Mappings | MIDI-003/004 `MIDIBindingList` of `cc:<ch>:<num>=<id>[;options]` lines under `settings.midi.mappings`; any other line is skipped on read and **dropped on the next save**. Learn (`MIDILearnSession`) accepts control changes 0–119 only. |
| Trigger targets | SHOW-001 `ShowCoordinator.next()` / `previous()` (the keyboard path `keyNextCue` does not show the controls); OUT-010 `ExternalDisplayCoordinator.setBlackout(_:)` / `toggleBlackout()` (announced by the status-event path on phase change). No Trails/freeze toggle has a one-call action without UI side effects. |
| Rate limits | OSC-009 `OSCRateLimiter` is specific to OSC sources and parameter targets; cue announcements are rate-limited on the announcer's `.cue` lane. |
| Test fakes | `ScriptedMIDIInputProvider` + `MIDIInputCoordinator.drain()`; DEBUG `-uitestFakeMIDI` panel with "Send Note" (note on 60, velocity 100). |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9).

- Q: Which actions can a note trigger? → A: A small set that already exists as one safe call: **Next cue**, **Previous cue** (SHOW-001, the keyboard path: no controls shown), **Black out (toggle)** and **Black out while held** (OUT-010). Go to a specific scene is MIDI-007's row and program-change/transport buttons are MIDI-008's; their action names can be added later without changing the stored form.
- Q: How do trigger and hold differ? → A: Each mapping has a mode. **Trigger** fires once on the note-on edge and ignores the note-off. **Hold** engages on the note-on edge and releases on the note-off (Black out while held: black while the key is down, restore when it is released).
- Q: Where is velocity 0 normalised? → A: At one point, the event's note edge (`on` when a note on has velocity > 0; `off` for a note off or a note on with velocity 0). Both parsers already produce note off for velocity 0, and the router reads only the edge, so a hand-made `.noteOn` event with value 0 is still a release.
- Q: How are note mappings stored? → A: In the same list as MIDI-003, `settings.midi.mappings`, one line each: `note:<ch 0-15>:<note 0-127>=<action>` with `;mode=hold` when held. Known actions: `cue.next`, `cue.previous`, `blackout`. CC lines are read and written exactly as before; note lines are kept (no longer dropped); unreadable or unknown `note:` lines are kept verbatim so a newer version's mappings survive. No new stored key.
- Q: Repeated note-on without a note-off? → A: Ignored: a mapping acts only on the up→down edge of its key, so a repeated note-on neither re-toggles a hold nor fires a trigger twice. At most one trigger per mapping per delivered batch (the input drains at most 30 times a second), which bounds a flood without a new rate limiter.
- Q: When are stuck notes cleared? → A: Every held key is released (holds release their action) when the input stops (listening off, background, no client), when a listed MIDI input goes away (the message carries no source, so all notes are released), on MIDI panic (controller 120 All Sound Off or 123 All Notes Off: that channel's keys; System Reset: all keys), and when a mapping is deleted or replaced while held.
- Q: What is announced? → A: Learn start, result and timeout on the `.midi` lane, as MIDI-003. The actions announce themselves through their own paths (cue steps on `.cue`, blackout on the status-event path), so a trigger adds no second announcement.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: How is a mapped note shown and spoken? → A: Shown as "Note C4 · Ch 1" (MIDI-002's sharp note names, channels 1–16) and spoken as "note C4 on channel 1". The note number is not shown separately; the MIDI Monitor already shows both.
- Q: Do note mappings share MIDI-003's one-step Undo, Cancel and 30 s learn timeout? → A: Yes. One learn session at a time for either kind (starting a note learn cancels a CC learn and the reverse); the same Cancel button, timeout, status line and Undo (Undo restores both lists as they were).
- Q: Does a note mapping have a velocity threshold? → A: No. Any note on with velocity 1–127 is a down edge; velocity 0 is always a release. A threshold adds a setting with no acceptance need.
- Q: Does blackout through a note work on the device screen alone, without an external display? → A: Yes. It is the same OUT-010 call as the controls' Black out button, which covers the device slot and every external slot.
- Q: Does Black out while held restore if the user restored by hand while the key is still held? → A: The release calls Restore only if the output is still blacked out and the hold was what blacked it out; otherwise it does nothing.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A pad steps to the next cue, however my controller sends note-off (Priority: P1) — MVP

A performer maps a pad (note C4) to Next cue. Each press steps exactly one cue. Their controller sends
"note on, velocity 0" instead of "note off" and uses running status; another sends real note offs. Both
behave identically.

**Why this priority**: It is the row's acceptance.

**Independent Test**: The three message sequences (note on v>0, note on v=0), (note on v>0, note off) and
(note on v>0, then running-status data bytes with v=0) produce identical note streams and identical
actions for trigger and hold mappings.

**Acceptance Scenarios**:

1. **Given** note 60 on channel 1 is mapped to Next cue, **When** the controller sends note on (velocity 100) then note on (velocity 0), **Then** the show steps one cue.
2. **Given** the same sequences sent as note on / note off, or with running status, **When** they are parsed and routed, **Then** the event streams and actions are identical.
3. **Given** a fake MIDI source, **When** it sends note on then velocity-0 note on for a Next cue mapping, **Then** the show moves exactly one cue.

---

### User Story 2 - Black out while I hold a key (Priority: P1)

The performer maps a key to Black out while held: the output is black while the key is down and restores
when it is released. Pressing the key again without a release (a glitchy controller) changes nothing.

**Why this priority**: It is the note-off half of the row.

**Independent Test**: Engage on note on, release on note off or velocity-0 note on; a repeated note on does
not toggle; a stuck key is released when the input stops or a source goes away.

**Acceptance Scenarios**:

1. **Given** a hold mapping to Black out, **When** the key goes down, **Then** the output blacks out; **When** it goes up (note off or velocity 0), **Then** the output restores.
2. **Given** the key is down, **When** a second note on arrives, **Then** nothing changes.
3. **Given** the key is down, **When** the MIDI input stops or a listed input disappears, **Then** the hold releases.

---

### User Story 3 - Learn a note (Priority: P2)

On MIDI Mappings, a "Note triggers" section lists the actions. The performer taps Learn on Next cue and
presses a pad; the row shows "Note C4 · Ch 1" and VoiceOver announces "Next cue mapped to note C4 on
channel 1."

**Independent Test**: A UI test with the stand-in MIDI input learns a note to Next cue in under 30 s.

**Acceptance Scenarios**:

1. **Given** learning for Next cue, **When** a note on arrives, **Then** it is bound, learn mode ends, and the learning note itself fires nothing.
2. **Given** learning for a glow parameter (MIDI-003), **When** a note arrives, **Then** it is not learned (CC learn is unchanged).

### Edge Cases

- A note on another channel than the mapping's: ignored (channel filtering).
- Note off for a key that is not down (for example the release of the learning press): ignored.
- A note that maps to nothing: ignored; CC mappings are unaffected by note traffic.
- Black out while held engaged when the output was already blacked out, or restored by hand while held: releasing does not restore it (the hold only undoes what it did).
- Learning a note while a CC learn is running: the CC learn is cancelled (one learn session at a time).
- Running status interrupted by a real-time byte (clock): the note stream is unchanged.
- A stored `note:` line with an unknown action or bad numbers: kept verbatim, not shown, not routed.
- One note per action and one action per note; learning a note already used moves it, as MIDI-003.
- At most 64 note mappings (the CC list keeps its own 64).

## Requirements *(mandatory)*

### Functional Requirements

- **MIDI-006-R1**: A note on with velocity 0 MUST be treated as a note off at one normalisation point used by every consumer of note events (both parsers and the router).
- **MIDI-006-R2**: The sequences (note on v>0, note on v=0), (note on v>0, note off) and (note on v>0, running-status note on v=0) MUST produce identical note-edge streams and identical actions.
- **MIDI-006-R3**: Each note mapping MUST bind one channel and note to one action with a mode, trigger or hold. Known actions: Next cue, Previous cue (trigger), Black out (trigger toggles, hold blacks out while held).
- **MIDI-006-R4**: A trigger mapping MUST fire once on the key's up→down edge and ignore note offs; a hold mapping MUST engage on the down edge and release on the up edge.
- **MIDI-006-R5**: A repeated note on while the key is down MUST NOT fire or toggle again; at most one trigger per mapping per delivered batch.
- **MIDI-006-R6**: Held keys MUST be released (holds release their action) when the input stops, when a listed MIDI input disappears, on All Sound Off / All Notes Off (that channel) and System Reset (all), and when a held mapping is deleted or replaced.
- **MIDI-006-R7**: Note mappings MUST be stored in `settings.midi.mappings` as `note:<ch>:<note>=<action>[;mode=hold]`; CC lines (MIDI-003/004) MUST read and write exactly as before; unknown or unreadable `note:` lines MUST be kept verbatim.
- **MIDI-006-R8**: MIDI Mappings MUST show a "Note triggers" section with one row per action (name, the mapped note as "Note C4 · Ch 1" or "Not mapped", Learn, Delete); learning binds the next note on (velocity > 0) and the learning press fires nothing. Note learn shares MIDI-003's Cancel, 30 s timeout, status line and one-step Undo; only one learn session runs at a time.
- **MIDI-006-R9**: Learn results and timeouts MUST be announced on the `.midi` lane; triggers add no announcement of their own.
- **MIDI-006-R10**: The model MUST build and pass its tests on Linux; the app MUST pass the repository checks. No new stored key, permission, usage string or network API.
- **MIDI-006-R11**: A DEBUG UI test MUST learn a note to a trigger with the stand-in MIDI input in under 30 s.

### Key Entities

- **Note edge**: on or off, derived from a note event (velocity 0 note on = off).
- **Note action**: Next cue, Previous cue, Black out; stored name `cue.next`, `cue.previous`, `blackout`.
- **Note binding**: channel, note, action, mode (trigger/hold), unknown segments kept.
- **Note router state**: the keys currently down, per mapping.

## Privacy review *(Constitution, Privacy)*

- A note mapping stores channel, note number, action and mode only: no device, endpoint, name or time.
- No permission, network ability or new stored key is added.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MIDI-006-S1**: For trigger and hold mappings, the three equivalent sequences give identical event streams and identical action lists (the row's acceptance).
- **MIDI-006-S2**: Repeated note on fires once; another channel fires nothing; stuck keys release on input stop, source removal and panic.
- **MIDI-006-S3**: Stored note lines round-trip; MIDI-003/004 lines are unchanged in a mixed list; unknown note lines are kept.
- **MIDI-006-S4**: With a fake MIDI source in the app, a Next cue mapping steps the show exactly once per press, and a hold mapping blacks out and restores.
- **MIDI-006-S5**: A UI test learns a note to Next cue in under 30 s.
- **MIDI-006-S6**: All repository checks pass and the package tests pass on the host (and Linux in CI).

## Assumptions

- The learnable CC parameters stay MIDI-003's four glow parameters.
- A physical controller check is the `{device}` task in the last stage; simulator results are never device evidence.
