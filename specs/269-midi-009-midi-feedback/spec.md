# Feature Specification: MIDI-009 MIDI Feedback

**Feature Branch**: `feature/midi-009` (spec directory `269-midi-009-midi-feedback`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MIDI-009 (MIDI feedback) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Send optional parameter state back to capable controllers." Acceptance, verbatim: "Connected mock
output receives bounded state updates without feedback loops." Priority P2, effort L, depends on MIDI-003 (integrated)."

Identifiers carry the roadmap ID: requirements `MIDI-009-R1…`, success criteria `MIDI-009-S1…`, research decisions
`MIDI-009-D1…`, tasks `MIDI-009-T01…`. Other features are cited by their own IDs: MIDI-001 (discovery), MIDI-002
(input), MIDI-003 (learn, mapping list), MIDI-004 (curve, Invert), MIDI-005 (14-bit), MIDI-011 (hot-plug), MIDI-012
(profiles), MIDI-013 (panic), MOD-002/MOD-007 (audio and LFO modulation), OSC-003 (OSC live values).

## Baseline: what exists today (audit of 2026-11-14, branch point `ff6d97a9`)

| Area | Today |
|---|---|
| Output | None. No output port, no `MIDISend`/`MIDISendEventList` anywhere; discovery (MIDI-001) lists destinations ("Output") but nothing is sent. |
| Input | One shared input port (MIDI 1.0 protocol) connected to every listed online input; messages carry no source (ADR-0038 Decision 7), drained at 30 Hz on the main actor. |
| Mappings | `cc:<ch>:<n>=<parameter>` lines plus `;`-separated options (`curve=`, `invert=1`, `hires=1`; unknown segments kept verbatim). One control per parameter, at most 64. |
| Values | Incoming CC → clamp → Invert → curve → range (`MIDIBindingValues`), 14-bit pairs through `MIDIHighResolutionTracker`. Live values replace the manual glow value as the base; MOD-002 layers (audio, LFO) are applied after the base. |
| Profiles | Lines copied verbatim, so any new segment round-trips. |
| Panic | Ends learn, drops queued input, releases held notes; never saves. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9).

- Q: How is feedback turned on? → A: Per mapping, off by default: a "Send feedback" switch on the mapping's options screen, stored as the segment `fb=1` on its `cc:` line (after `hires=1`, before unknown segments). No new UserDefaults key, no global switch.
- Q: Which output receives feedback? → A: Destinations paired with the inputs being listened to: an online destination of the same (non-empty) device as a listed online input, or, for virtual endpoints of other apps, a virtual destination with the same name as a listed virtual input. Messages carry no source (ADR-0038 Decision 7), so feedback cannot target "the one controller that sent"; pairing by device keeps it on controllers the user already connected. No destination picker in this row.
- Q: What value is sent? → A: The parameter's base value (the manual value, or the live MIDI/OSC value that replaces it), converted back to a controller value through the mapping's range, curve and Invert by searching the controller values for the one whose mapped value is nearest. Audio and LFO modulation (MOD-002, MOD-007) is never sent, so a modulated parameter cannot flood the output.
- Q: How is it bounded? → A: Per control at most 30 updates per second, coalesced to the latest value; only a change of the 7-bit (or 14-bit) controller value is sent; at most 16 messages per 30 Hz tick in total, round-robin so no control starves.
- Q: How are feedback loops prevented? → A: A value received from the controller marks that control's value as already shown on the controller and opens a 100 ms echo window in which nothing is sent for it; a received control change that exactly matches a byte we sent within the last 100 ms is treated as the device's echo and dropped. A loopback (output wired to input) settles after at most one message per change.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A controller's LEDs or motor faders follow the app (Priority: P1) — MVP

A performer has Glow intensity mapped to a knob with LED rings. They turn on "Send feedback" for that mapping. When a
scene change, the on-screen slider or an OSC message changes Glow intensity, the knob's LED ring moves to the new value.

**Why this priority**: The row's observable behavior.

**Independent Test**: With a mock output and a manual clock, change a mapped parameter's value and read the messages
the output received.

**Acceptance Scenarios**:

1. **Given** a feedback mapping on CC 7 channel 1, **When** the parameter changes once, **Then** the output receives exactly one control change (channel 1, CC 7) with the controller value for that parameter value.
2. **Given** an inverted mapping with a curve, **When** the parameter is at its minimum, **Then** 127 is sent; at its maximum, 0.
3. **Given** a 14-bit feedback mapping on CC 7, **When** the parameter changes, **Then** CC 7 (coarse) then CC 39 (fine) are sent.
4. **Given** a mapping without feedback, **When** the parameter changes, **Then** nothing is sent.

### User Story 2 - Feedback never floods or loops (Priority: P1)

**Acceptance Scenarios**:

1. **Given** a feedback mapping, **When** the parameter changes 1000 times within one second, **Then** at most 30 messages (plus at most one) are sent for it in that second and the last message carries the final value.
2. **Given** a feedback mapping, **When** the controller itself moves the parameter, **Then** nothing is echoed back to it.
3. **Given** the output wired straight back to the input, **When** the parameter changes, **Then** at most one message per change is sent and the system is silent afterwards over thousands of ticks.
4. **Given** a device that echoes what it receives, **When** its echo arrives, **Then** the echo does not change the parameter.

### User Story 3 - Turn feedback on for one mapping (Priority: P2)

**Acceptance Scenarios**:

1. **Given** a mapping, **When** the user turns on "Send feedback" on its options screen, **Then** the line is saved with `fb=1` at once, announced, and the row's summary says "feedback".
2. **Given** a profile saved with a feedback mapping, **When** it is exported, imported and applied, **Then** the line is byte-identical.

### Edge Cases

- No paired destination (input-only controller, or listening off): nothing is sent and nothing is queued for later.
- The app in the background or listening off: the input stops, so feedback stops; nothing is sent while away.
- MIDI panic: pending feedback is dropped and the current values are taken as shown; nothing is sent until a value changes again.
- A paired destination appears (controller plugged in): the current value of every feedback mapping is sent once, within the per-tick cap.
- A curve with a flat part (piecewise with equal y): several controller values give the same parameter value; the one the controller last sent is kept when it still matches, otherwise the lowest.
- A parameter value outside the mapping range (clamped by another source): the nearest end is sent.
- An older build reading `fb=1` keeps it as an unknown segment and sends nothing.

## Requirements *(mandatory)*

### Functional Requirements

- **MIDI-009-R1**: Each `cc:` mapping MUST have a feedback option, off by default, stored as the segment `fb=1` after `hires=1` and before unknown segments; lines without it MUST stay byte-identical to MIDI-005's.
- **MIDI-009-R2**: For a feedback mapping, a change of the parameter's base value from any source (UI, scene, OSC, another controller) MUST send the mapped control change; audio and LFO modulation MUST NOT be sent.
- **MIDI-009-R3**: The controller value MUST be the one whose mapped parameter value (range, curve, Invert; 7- or 14-bit) is nearest the parameter value; for a 14-bit mapping the coarse controller (value ≫ 7) MUST be sent before the fine controller n+32 (value & 0x7F).
- **MIDI-009-R4**: Messages MUST be sent only when the quantised controller value differs from the value last sent or received for that control.
- **MIDI-009-R5**: Each control MUST send at most 30 updates per second, coalescing to the latest value, and the final value MUST always be delivered.
- **MIDI-009-R6**: At most 16 messages MUST be sent per tick in total, serving controls round-robin.
- **MIDI-009-R7**: A value applied from the controller MUST be taken as the controller's current value and MUST suppress feedback for that control for 100 ms.
- **MIDI-009-R8**: A received control change that equals a byte sent on the same channel and controller within the last 100 ms MUST be dropped as an echo (once per sent byte).
- **MIDI-009-R9**: Feedback MUST go only to online, non-network destinations paired with a listed online input (same device name; virtual: same name), through the public CoreMIDI output API with MIDI 1.0 Universal MIDI Packets; no network MIDI.
- **MIDI-009-R10**: Feedback MUST stop while the input is not receiving (listening off, background) and on panic (pending dropped, current values taken as shown).
- **MIDI-009-R11**: When paired destinations are added, the current value of every feedback mapping MUST be sent once (bounded by R5 and R6).
- **MIDI-009-R12**: The options screen MUST offer a "Send feedback" switch that saves at once and announces on the `.midi` lane, with no Undo step; the curve summary MUST add ", feedback" when on.
- **MIDI-009-R13**: The feedback logic MUST be pure Swift with an injected clock and an output protocol, and pass on Linux.

### Key Entities

- **Feedback flag**: one more option of a `cc:` binding (`fb=1`).
- **Control feedback state** (memory only): the value last shown on the controller, the pending value, the time of the last send and the end of the echo window.
- **Sent-byte record** (memory only): the last byte sent per channel and controller and when, for echo detection.
- **Feedback message**: channel, controller, value (a MIDI 1.0 control change).

## Privacy review *(Constitution, Privacy)*

- No new UserDefaults key, file, network API or permission. Sending to a local MIDI destination needs no permission.
- Only control changes of mapped controls are sent: no device identity, name or user data leaves the app; nothing is logged or stored.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MIDI-009-S1**: One parameter change sends exactly one correct control change to the mock output.
- **MIDI-009-S2**: 1000 rapid changes stay within 30 messages per second per control (plus one) and the final value is delivered.
- **MIDI-009-S3**: A controller's own value produces no echo.
- **MIDI-009-S4**: A loopback (output into input) sends at most one message per change and is silent over at least 3000 ticks afterwards.
- **MIDI-009-S5**: A 14-bit mapping sends coarse then fine.
- **MIDI-009-S6**: The option round-trips through the mapping line and a profile export and import.
- **MIDI-009-S7**: In the app, a mock destination receives feedback for a feedback mapping; a UI test turns the switch on in under 30 s; all repository checks and package tests pass.

## Assumptions

- MIDI 2.0 (32-bit) controller values are out of scope: the output sends MIDI 1.0 protocol packets, as the input reads them.
- A physical controller with motorised faders or LED rings is checked in the `{device}` task in the last stage.
- No destination picker: pairing by device covers controllers that are both input and output; a picker can be a later row.
