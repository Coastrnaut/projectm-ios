# Feature Specification: MIDI-002 MIDI Input Monitor

**Feature Branch**: `feature/midi-002` (spec directory `125-midi-002-midi-input-monitor`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (MIDI-002-T01-T19 verified on the Mac with the scripted MIDI system; device task T20 `{device}` open)

**Input**: User description: "Implement MIDI-002 (MIDI input monitor) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Show incoming message type,
channel and value in a privacy-safe monitor." Acceptance, verbatim: "Injected CC and note events
render correctly without recording identifiers." Verification: unit tests with fake MIDI; a
physical controller in the last stage. Depends on MIDI-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MIDI-002-R1…`, success criteria `MIDI-002-S1…`, tasks `MIDI-002-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `c3bcec81`)

The row's gap status is "Gap candidate". The audit confirms a full gap.

| Area | Today |
|---|---|
| MIDI messages | None. MIDI-001 (ADR-0038) lists endpoints only: its CoreMIDI provider creates one client and no ports, and states that no MIDI message is received or parsed. No parser, no input port, no message model exists anywhere in `Packages/` or `Apps/`. |
| Endpoints | `MIDIEndpointDiscovery` (PerformanceControl) delivers an ordered `MIDIEndpointList` with stable `MIDIEndpointID`s, local endpoints only (network MIDI hidden, no Bluetooth pairing). `MIDIDiscoveryCoordinator` runs it while "Listen for MIDI devices" (`settings.midi.enabled`, off by default) is on and the app is in the foreground. |
| Settings | `MIDISettingsSection` shows the toggle, status and endpoint rows; a DEBUG stand-in (`-uitestFakeMIDI`) plugs "Fake Keys" (one input, one output). |
| Real-time pattern | AudioCore's `SPSCRingBuffer`: preallocated storage, `Synchronization.Atomic` indices, documented overflow policy; "storage addresses unchanged" tests (VIS-003) check that a hot path allocates nothing. |
| Announcements | `AccessibilityAnnouncer` with kind `.midi` (MIDI-001-R11); `scripts/check_status_events.py` forbids direct posts in listed files. |
| Later rows | MIDI-003 (learn), MIDI-004 (CC scaling), MIDI-005 (14-bit), MIDI-006 (note triggers) and MIDI-007 (program change) need the same received messages. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Which messages does the monitor show? → A: Every MIDI 1.0 channel message (note on, note off, control change, program change, pitch bend, channel pressure, poly pressure), system exclusive as its length only, the transport messages start, continue, stop and reset, and the system common messages (song position, song select, time code quarter frame, tune request). Timing clock and active sensing are counted, not listed (MIDI-002-R4). A note on with velocity 0 is shown as a note off (MIDI 1.0's rule; MIDI-006 will rely on the same model).
- Q: What does "without recording identifiers" mean? → A: A monitor entry and every message the app keeps carry only the message itself (type, channel, number, value) and a time relative to when the monitor opened. No entry, counter, status text, diagnostic, log line or stored setting contains a MIDI endpoint's unique number, its stable ID, its name, its device, entity or manufacturer name, or which source sent the message. Nothing about messages is written to disk or kept after the monitor closes (MIDI-002-R7, R8).
- Q: Where does the monitor live? → A: A "MIDI Monitor" screen opened from the MIDI section in Settings, available while listening is on. Rejected: an overlay on the visualizer (it would cover the visuals during a show and needs its own motion and contrast review).
- Q: When is MIDI received? → A: Only while listening is on, the app is in the foreground and at least one feature needs messages (in this row, only while the monitor screen is open). Closing the monitor stops receiving; nothing runs in the background (MIDI-002-R1).
- Q: Which sources are received? → A: Every input listed by MIDI-001 (local only: USB, other apps' virtual sources, system-connected Bluetooth); network MIDI stays hidden and is never connected. Choosing sources one by one is left to the mapping rows.
- Q: How many entries does the monitor keep? → A: The newest 64, newest first, in memory only; older entries fall off. Clear empties it; closing the monitor drops it.
- Q: Does live traffic speak to VoiceOver? → A: No. A busy controller sends dozens of messages per second; announcing them would make VoiceOver unusable. Rows are readable one by one with combined labels, and pause freezes the list so they can be read (MIDI-002-R10).
- Q: Does the visualizer get a "MIDI receiving" badge (as MIDI-001 deferred to this row)? → A: No. The monitor receives only while its own screen is open, so the screen is the indicator. MIDI-003's learn mode can revisit it.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: How big is the queue between the MIDI system and the screen, and what happens when it is full? → A: 512 messages; when full, the newest message that does not fit is dropped and counted ("N dropped" in the summary line). At a 30 Hz drain that is over 15,000 messages per second, far above a MIDI cable's ~3,100; drop-newest keeps the producer from ever touching the consumer's position (MIDI-002-R5). Rejected: drop-oldest (needs the producer to move the reader's index) and an unbounded queue (constitution VII).
- Q: How is the time of an entry shown? → A: Seconds since the monitor opened (or was last cleared) with two decimals, for example "12.40 s"; the spoken label leaves the time out so rows stay short. Rejected: wall-clock time of day (records when the user played, which nothing needs).
- Q: How are notes named? → A: The number plus its name with middle C (60) as C4 and sharps only, for example "60 C4", "61 C♯4"; spoken "note 60 C sharp 4". Rejected: C3 for 60 (some apps use it, but C4 matches the MIDI Association's and scientific pitch naming).
- Q: Where is the monitor opened when listening is off? → A: The "MIDI Monitor" row is always in the MIDI section and opens the screen; while listening is off (or MIDI is unavailable) the screen says "Turn on Listen for MIDI devices to see messages." and receives nothing; turning listening off while it is open stops receiving at once (MIDI-002-R1).
- Q: How fast does the screen update? → A: The queue is drained on the display's refresh, capped at 30 updates per second; messages within one update are added together, newest first. 30 Hz is faster than anyone can read and keeps the list cheap (MIDI-002-R5).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I see what my controller sends (Priority: P1) — MVP

A performer turns on "Listen for MIDI devices", opens the MIDI Monitor and moves a fader and plays
a key on the controller. Each message appears at the top of the list at once: "Control change",
channel 1, controller 7, value 100; "Note on", channel 1, note 60 (C4), velocity 100.

**Why this priority**: It is the row's behaviour and acceptance, and the way a performer checks a
controller before mapping it (MIDI-003).

**Independent Test**: A fake MIDI system injects a control change and a note: the monitor shows
the two entries with the expected type, channel, number and value text.

**Acceptance Scenarios**:

1. **Given** listening is on and the monitor is open, **When** a control change (channel 1, controller 7, value 100) arrives, **Then** a new top entry reads "Control change", "Ch 1", "CC 7", "100", and VoiceOver reads "Control change, channel 1, controller 7, value 100".
2. **Given** the monitor is open, **When** a note on (channel 10, note 60, velocity 127) and then a note on with velocity 0 for the same note arrive, **Then** the entries read "Note on … 127" and "Note off … 0", newest first.
3. **Given** the monitor is open, **When** a pitch bend at centre arrives, **Then** its value reads 8192 (range 0–16383).
4. **Given** 70 messages arrived, **When** the list is shown, **Then** it holds the newest 64.

---

### User Story 2 - I can pause and clear while I check (Priority: P2)

A performer pauses the monitor to read an entry while the controller keeps sending, then clears it.

**Why this priority**: A live list moving under the finger cannot be read; clearing starts a fresh check.

**Independent Test**: Inject, pause, inject more: the list does not change; resume: new messages
appear again; clear: the list is empty.

**Acceptance Scenarios**:

1. **Given** the monitor is paused, **When** messages arrive, **Then** the list does not change and a line states how many messages arrived while paused.
2. **Given** a paused monitor, **When** the user resumes, **Then** only messages after resuming are added.
3. **Given** entries are shown, **When** the user clears, **Then** the list and counters are empty.

---

### User Story 3 - Nothing about my devices is recorded (Priority: P1)

A user wants to know the monitor cannot be used to fingerprint their equipment and keeps nothing.

**Why this priority**: The row's acceptance ("without recording identifiers") and the constitution's privacy rules.

**Independent Test**: Inject messages from a fake source with a distinctive name and number; scan
every entry, counter, status text, log line and stored setting: neither appears; close the monitor:
nothing is left.

**Acceptance Scenarios**:

1. **Given** messages from a source named "Secret Keys" with unique number 0x5EC2E7, **When** entries, counters, status texts, the app's log and its stored settings are scanned, **Then** neither the name nor the number (decimal, hexadecimal or as a MIDI-001 ID) appears.
2. **Given** the monitor shows entries, **When** it is closed and reopened, **Then** it is empty.
3. **Given** listening is off or the app is in the background, **When** a controller sends, **Then** nothing is received and no input is connected.

### Edge Cases

- Running status (a byte stream that omits repeated status bytes) is decoded as repeated messages.
- Real-time bytes (clock, start, stop) arriving between the bytes of another message do not break it.
- System exclusive of any length becomes one entry with its byte count; its contents are never kept.
- A flood beyond what the screen can show (a ribbon controller, thousands of messages per second): the bounded queue drops the newest messages it has no room for and the monitor says how many were dropped; nothing grows without bound.
- Timing clock at 24 per quarter note: counted in one summary line, never listed.
- Data bytes without a status, or a status cut short by another status: ignored, never shown as a wrong message.
- A source unplugged while the monitor is open: its messages stop; MIDI-001's list updates; reconnecting resumes.
- Listening turned off while the monitor is open: receiving stops and the monitor says listening is off.
- Platforms without a MIDI service (Linux CI): the message model and decoders build and pass their tests; receiving reports unavailable.

## Requirements *(mandatory)*

### Functional Requirements

- **MIDI-002-R1**: The app MUST receive MIDI messages only while listening is on (MIDI-001's toggle), the app is in the foreground and at least one feature needs them (the open monitor in this row); otherwise no input is open and no source is connected.
- **MIDI-002-R2**: While receiving, the app MUST connect every input MIDI-001 lists and only those (never a network MIDI endpoint), following plug and unplug changes.
- **MIDI-002-R3**: Messages MUST be decoded per MIDI 1.0: note on, note off (and note on with velocity 0 as note off), control change, program change, pitch bend (14-bit, 0–16383), channel pressure, poly pressure, the system common and transport messages, and system exclusive as its length only. Byte-stream input MUST support running status and real-time bytes interleaved inside other messages, and ignore stray data bytes.
- **MIDI-002-R4**: Timing clock and active sensing MUST be counted, not listed; the monitor shows their counts in one summary line.
- **MIDI-002-R5**: The path from the system's MIDI callback to the queue MUST be bounded and real-time safe: no allocation, lock, logging or main-thread hop per message, a preallocated bounded queue of 512 messages with a tested overflow policy (drop the newest message that does not fit, counted), and the screen drains the queue on the display refresh, at most 30 times per second.
- **MIDI-002-R6**: Each entry MUST show the message type, the channel (1–16, for channel messages), the number (note with its name, controller or program) where it applies, the value, and the time since the monitor opened or was last cleared ("12.40 s"); notes show their number and name with middle C (60) as C4; VoiceOver reads one combined label per row (for example "Control change, channel 1, controller 7, value 100").
- **MIDI-002-R7**: Entries, counters, status texts, diagnostics and logs MUST NOT contain a MIDI endpoint's unique number, stable ID, name, or device, entity or manufacturer name, nor which source sent a message. Message contents MUST NOT be logged.
- **MIDI-002-R8**: The monitor MUST keep at most 64 entries (newest first) in memory only; nothing about messages is stored on disk or in settings, and closing the monitor drops entries and counters. No new stored setting is added.
- **MIDI-002-R9**: The monitor MUST offer Pause/Resume (paused: the list is frozen, arriving messages are counted and not added) and Clear (entries and counters emptied).
- **MIDI-002-R10**: Live traffic MUST NOT be announced to VoiceOver; the monitor posts no announcement directly (status events check).
- **MIDI-002-R11**: The message model, decoders and queue MUST build and pass their tests on Linux; the system input compiles only where the system MIDI framework exists, and elsewhere receiving reports unavailable.
- **MIDI-002-R12**: A DEBUG-only stand-in (MIDI-001's `-uitestFakeMIDI`) MUST let a UI test inject a control change and a note into the monitor; Release builds never create it.
- **MIDI-002-R13**: The built app MUST still pass the network symbol scan, the privacy manifest check and the source compliance check; no permission or usage string is added.
- **MIDI-002-R14**: The received-message model MUST be reusable by MIDI-003 onward: it names the message kind, channel and number as a control key and gives a normalized value (7-bit values over 127, pitch bend over 16383).
- **MIDI-002-R15**: The MIDI section MUST always offer a "MIDI Monitor" row; while listening is off or MIDI is unavailable the monitor says "Turn on Listen for MIDI devices to see messages." and receives nothing.

### Key Entities

- **MIDI message (event)**: kind, channel (0–15; none for system messages), number (note, controller or program), value (velocity, controller value, pressure, 14-bit bend, system exclusive length), monotonic timestamp. No source.
- **Monitor entry**: sequence number, the message, time since the monitor opened; display and spoken texts.
- **Monitor counters**: clock, active sensing, received while paused, dropped by the queue.
- **Input state**: off, receiving, unavailable (system error code only).

## Privacy review *(Constitution, Privacy)*

- Messages are shown while the monitor is open and dropped when it closes; nothing is stored, logged, exported or sent (MIDI-002-R7, R8).
- Entries name no source, so the monitor cannot list or fingerprint equipment.
- No permission is requested and no network ability is added (MIDI-002-R13).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MIDI-002-S1**: Injected control change and note messages appear in the monitor with exactly the expected type, channel, number, value and spoken texts (the row's acceptance, first half).
- **MIDI-002-S2**: After injection from a source with a distinctive name and number, no entry, counter, status text, log line or stored setting contains either (the row's acceptance, second half).
- **MIDI-002-S3**: A decoder table covers every message type, edge values (0 and 127; bend 0, 8192, 16383), note on with velocity 0, running status, system exclusive and real-time bytes interleaved, with no wrong message.
- **MIDI-002-S4**: A flood larger than the queue keeps memory fixed, drops only what does not fit and reports the dropped count; 10,000 messages through the callback path leave the queue's storage where it was.
- **MIDI-002-S5**: Pause, resume, clear and the 64-entry cap behave as R8 and R9 state.
- **MIDI-002-S6**: A UI test opens the monitor with the stand-in MIDI system, injects a control change and a note, and reads both rows, in under 30 s.
- **MIDI-002-S7**: The built app passes the network symbol scan and privacy manifest check; compliance, permission catalog, status events and motion policy checks pass.
- **MIDI-002-S8** `{device}`: On a physical device with a USB MIDI controller, moving a fader and playing a key show the right entries within a moment, and closing the monitor stops receiving.

## Assumptions

- The monitor is a diagnostic screen; 64 entries are enough to check a controller, and 30 to 60 updates per second keep up with any human gesture.
- MIDI-001's endpoint list is the source of truth for which inputs exist.
- MIDI 2.0 messages are out of scope: the app asks the system for MIDI 1.0 messages.
- Learn, scaling, note triggers and program change mappings (MIDI-003 to MIDI-007) are out of scope; they reuse this row's message model and input service.
