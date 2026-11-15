# Feature Specification: MIDI-005 MIDI 14-bit Controls

**Feature Branch**: `feature/midi-005` (spec directory `266-midi-005-14-bit-controls`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MIDI-005 (MIDI 14-bit controls) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Combine paired high/low-resolution controller messages when supported." Acceptance, verbatim: "Test
MSB/LSB pair produces expected 14-bit normalized value." Priority P2, effort M, depends on MIDI-003 (integrated)."

Identifiers carry the roadmap ID: requirements `MIDI-005-R1…`, success criteria `MIDI-005-S1…`, research decisions
`MIDI-005-D1…`, tasks `MIDI-005-T01…`. Other features are cited by their own IDs: MIDI-002 (input, parsers, UMP
decoder), MIDI-003 (learn and the mapping list), MIDI-004 (curve and Invert options), MIDI-008 (CC buttons),
MIDI-012 (profiles), ACC-004 (announcer lanes).

## Baseline: what exists today (audit of 2026-11-14, branch point `427ff698`)

| Area | Today |
|---|---|
| Messages | MIDI-002 decodes MIDI 1.0 byte streams and UMP words of the MIDI 1.0 protocol (message type 0x2) into `MIDIEvent` (kind, channel, number, value); MIDI 2.0 channel voice packets (type 0x4) are skipped by their word count. The system input port is created with the MIDI 1.0 protocol. |
| Values | `MIDIEvent.normalizedValue` is value / 127 for a control change. Each `cc:` binding drives one continuous parameter: clamp, Invert, MIDI-004 curve, then the parameter's range. Newest value per parameter per batch. |
| Learn | The first eligible control change (controller 0–119) of a batch binds the selected parameter; the learning message applies no value. |
| Stored form | `cc:<ch>:<n>=<parameter>` plus MIDI-004 segments (`curve=`, `invert=1`); unknown segments are kept verbatim. Profiles (MIDI-012) copy lines verbatim. |
| 14-bit | None: a 14-bit controller's CC n (coarse) and CC n+32 (fine) are two separate 7-bit controls. Learning binds the coarse CC and its fine messages are ignored, so the parameter moves in 128 steps. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9).

- Q: Which controllers pair? → A: The MIDI 1.0 rule: controllers 0–31 are the coarse part (MSB) and controller n+32 (32–63) on the same channel is its fine part (LSB). Only a mapping on controller 0–31 can be 14-bit.
- Q: What value does a pair give? → A: (MSB × 128 + LSB) / 16383, so MSB 0x40 with LSB 0x00 is 8192/16383, 0x7F/0x7F is exactly 1 and 0/0 exactly 0; then MIDI-004's Invert and curve and the parameter's range apply as for a 7-bit value.
- Q: What does a coarse message alone do? → A: It sets the coarse part and resets the fine part to 0 (MIDI 1.0: a new MSB clears the LSB) and updates the value at once. A fine message changes only the low 7 bits of the last coarse value; a fine message before any coarse one gives no value.
- Q: What about controllers that send only the coarse part? → A: Until the first fine message of that pair arrives, coarse messages read as 7-bit (value / 127, so the top still reaches the maximum). After the first fine message the pair reads as 14-bit for the rest of the session.
- Q: What does "when supported" mean? → A: Both: learn detects a 14-bit control (the fine controller n+32 on the same channel within 500 ms after the learning message, or later in the same batch) and marks the mapping 14-bit; and each mapping on controller 0–31 has a "14-bit control" switch on its options screen to set or clear it by hand.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A 14-bit knob drives a parameter smoothly (Priority: P1) — MVP

A performer maps a high-resolution fader (CC 7 coarse, CC 39 fine) to Glow intensity. Moving the fader changes the
glow in 16384 steps instead of 128, so slow fades no longer step visibly.

**Why this priority**: The row's acceptance.

**Independent Test**: Through the stand-in MIDI source, send coarse and fine pairs to a 14-bit mapping and read the
normalized value and the live parameter value.

**Acceptance Scenarios**:

1. **Given** a 14-bit mapping on CC 7, **When** CC 7 = 0x40 then CC 39 = 0x00 arrive, **Then** the normalized value is 8192/16383.
2. **Given** the same mapping, **When** 0x7F/0x7F arrive, **Then** the value is exactly 1; **when** 0/0 arrive, exactly 0.
3. **Given** a coarse 0x40, **When** several fine messages follow, **Then** each sets the low 7 bits of the same coarse value.
4. **Given** coarse 0x40 with fine 0x7F, **When** a new coarse 0x41 arrives, **Then** the fine part resets to 0 (value 0x41 × 128 / 16383).
5. **Given** a 14-bit mapping, **When** the app receives fine steps of one coarse value, **Then** the live parameter takes values between two 7-bit steps.

### User Story 2 - Learn recognizes a 14-bit control (Priority: P1)

**Acceptance Scenarios**:

1. **Given** learn is armed, **When** CC 7 then CC 39 arrive (same batch or within 500 ms), **Then** the mapping is stored 14-bit and "14-bit" is announced.
2. **Given** learn is armed, **When** only CC 7 arrives, **Then** the mapping is 7-bit as before.
3. **Given** learn is armed, **When** CC 50 (not 0–31) is learned, **Then** no pairing is offered or detected.

### User Story 3 - Set or clear 14-bit by hand (Priority: P2)

**Acceptance Scenarios**:

1. **Given** a mapping on CC 0–31, **When** the user turns on "14-bit control" on its options screen, **Then** the line is saved with the flag at once, announced, and the next messages are read as pairs.
2. **Given** a mapping on CC 32–119, **When** its options screen opens, **Then** no 14-bit switch is shown.

### Edge Cases

- A controller that sends only coarse messages on a 14-bit mapping still reaches both ends (7-bit fallback).
- A fine message before any coarse one: no value.
- Fine messages on another channel or for another coarse controller: ignored by this mapping.
- CC n+32 also bound to another parameter by the user: it still drives that parameter as well (the user's choice).
- A stored `hires=1` on a controller 32–119 is kept verbatim but has no effect.
- An older build reading a 14-bit line keeps `hires=1` as an unknown segment and drives the coarse part as 7-bit.

## Requirements *(mandatory)*

### Functional Requirements

- **MIDI-005-R1**: A 14-bit mapping MUST combine coarse controller n (0–31) and fine controller n+32 on the same channel into (MSB × 128 + LSB) / 16383.
- **MIDI-005-R2**: A coarse message MUST reset the fine part to 0 and update the value; a fine message MUST update only the low 7 bits of the last coarse value; a fine message before any coarse one MUST give no value.
- **MIDI-005-R3**: Until the first fine message of a pair is received, coarse messages of a 14-bit mapping MUST read as 7-bit (value / 127).
- **MIDI-005-R4**: MIDI-004's Invert and curve and the parameter range MUST apply to the 14-bit normalized value exactly as to a 7-bit one.
- **MIDI-005-R5**: Learn MUST mark a new mapping on controller 0–31 as 14-bit when controller n+32 on the same channel arrives later in the learning batch or within 500 ms after it, and announce it on the `.midi` lane.
- **MIDI-005-R6**: The options screen of a mapping on controller 0–31 MUST offer a "14-bit control" switch that saves at once and announces on the `.midi` lane; mappings on other controllers MUST NOT show it.
- **MIDI-005-R7**: The flag MUST be stored as the segment `hires=1` on the mapping's `cc:` line (after `curve=` and `invert=1`, before unknown segments); a line without it MUST read as 7-bit, and lines without the flag MUST stay byte-identical to MIDI-004's.
- **MIDI-005-R8**: Profiles (MIDI-012) MUST round-trip lines with and without the flag byte for byte, and count both as controls.
- **MIDI-005-R9**: The pairing state MUST be pure Swift, allocation-free per message and pass on Linux.
- **MIDI-005-R10**: The mapping's curve summary MUST add ", 14-bit" when the flag is on.

### Key Entities

- **14-bit flag**: one more MIDI-004 option of a `cc:` binding.
- **Pair state**: per channel and coarse controller, the last coarse value, last fine value and whether any fine value was seen (memory only).

## Privacy review *(Constitution, Privacy)*

- No new UserDefaults key, file, network API or permission. The flag is one more segment on an existing mapping line.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MIDI-005-S1**: A coarse/fine pair gives the expected 14-bit normalized value: 0x40/0x00 → 8192/16383, 0x7F/0x7F → 1, 0/0 → 0 (the row's acceptance).
- **MIDI-005-S2**: Several fine messages after one coarse, and a new coarse resetting the fine part, give the values in R2.
- **MIDI-005-S3**: A coarse-only controller on a 14-bit mapping reaches 0 and 1.
- **MIDI-005-S4**: Learn detects the pair and stores `hires=1`; a single controller stays 7-bit.
- **MIDI-005-S5**: Profiles round-trip with and without the flag.
- **MIDI-005-S6**: In the app, a 14-bit mapping sets the parameter to a value between two 7-bit steps.
- **MIDI-005-S7**: A UI test turns the switch on in under 30 s, and all repository checks and package tests pass.

## Assumptions

- MIDI 2.0 high-resolution controller packets are out of scope: the input port uses the MIDI 1.0 protocol, so the system delivers MIDI 2.0 devices as MIDI 1.0 messages.
- A physical 14-bit controller check is the `{device}` task in the last stage.
