# Feature Specification: MIDI-013 MIDI Panic

**Feature Branch**: `feature/midi-013` (spec directory `183-midi-013-panic`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MIDI-013 (MIDI panic) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Release held note states and clear stuck triggers on user command." Acceptance, verbatim: "After
panic no active note gates remain in mapping engine." Priority P1, effort S, depends on MIDI-006 (integrated)."

Identifiers carry the roadmap ID: requirements `MIDI-013-R1…`, success criteria `MIDI-013-S1…`, research decisions
`MIDI-013-D1…`, tasks `MIDI-013-T01…`. Other features are cited by their own IDs: MIDI-003 (learn and the mapping
list), MIDI-006 (note triggers, hold mode), MIDI-007 (scene selection), MIDI-008 (CC buttons, real-time sources, the
shared press rule), MIDI-011 (source loss), OUT-010 (output blackout), ACC-004 (announcer lanes).

## Baseline: what exists today (audit of 2026-11-14, branch point `11cf8cd0`)

| Area | Today |
|---|---|
| Held keys | MIDI-006/008 keep the set of bound keys that are down (notes, CC buttons) in one press rule shared by every trigger source, plus per-key last-press times (the 30 ms repeat window) and the keys pressed in the current batch. |
| Automatic release | All Sound Off / All Notes Off (CC 120/123) release one channel's keys; System Reset releases all keys; the input stopping, a listed input going away and a lost source (MIDI-011) release all keys through one path that also undoes a "Black out while held". |
| Learn | One learn session at a time (CC, trigger or scene), ended by Cancel, a 30 s timeout or the input stopping. |
| Pending input | Messages wait in the input's queue until the next display tick (at most 30 Hz) delivers them as one batch. |
| User command | None: a user whose controller left a key stuck (lost note-off, a pad held during a profile change) can only unplug the device or turn listening off. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9).

- Q: What does panic release? → A: Every held trigger key (notes and CC buttons) through the same release path as source loss, so a "Black out while held" is undone exactly as on a key's release; then the press rule forgets everything (down keys, last-press times, same-batch presses).
- Q: What else does it clear? → A: Messages still waiting in the input queue (they were sent before the command and would re-press keys) and any learn session in progress (cancelled with no binding).
- Q: What does it never change? → A: The stored mappings (byte for byte), the current scene or cue, live CC parameter values (they are positions, not gates), listening and the connected inputs.
- Q: Where is the command? → A: A "MIDI Panic" button in the MIDI section of Settings, the keyboard shortcut ⌘⇧M on the visualizer and in Settings, a VoiceOver custom action "MIDI panic" on the visualizer, and an optional mappable trigger `midi.panic` in the Transport rows of MIDI Mappings (a trigger line, MIDI-006 format).
- Q: What is announced? → A: "MIDI reset" on the `.midi` lane, every time the command runs (also when nothing was held, so the user hears that the command was taken).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Clear a stuck controller in one action (Priority: P1) — MVP

A performer's pad sticks (its note-off was lost) while it is mapped to "Black out while held", so the output stays
black; a CC button and two more keys are also down, and a learn was left running. They press MIDI Panic. The output
comes back, nothing is held, learning ends, and their mappings and current scene are untouched. Pressing the pad again
works normally.

**Why this priority**: The row's acceptance.

**Independent Test**: Through the stand-in MIDI source, hold three bound notes (one on "Black out while held"), hold a
bound CC button down, start a learn session, run panic. No keys are down, the press rule holds nothing, the blackout is
restored, learning is cancelled, the stored mapping lines are byte-identical, and a later press fires normally.

**Acceptance Scenarios**:

1. **Given** the held keys, CC button and learn session above, **When** panic runs, **Then** no active gates remain, the blackout the hold made is restored, learning is cancelled with no binding and "MIDI reset" is announced on the `.midi` lane.
2. **Given** the same state, **When** panic runs, **Then** the stored mapping lines are byte-identical and the current scene is unchanged.
3. **Given** panic just ran, **When** a bound key is pressed again (even within 30 ms of its earlier press), **Then** it fires as a fresh press.

### User Story 2 - Panic from the keyboard, VoiceOver or a controller (Priority: P1)

**Acceptance Scenarios**:

1. **Given** a hardware keyboard, **When** the user presses ⌘⇧M on the visualizer or in Settings, **Then** panic runs.
2. **Given** VoiceOver on the visualizer, **When** the user picks the "MIDI panic" action, **Then** panic runs.
3. **Given** a key learned to "MIDI panic" in MIDI Mappings, **When** it is pressed, **Then** panic runs (and its own release is ignored).

### User Story 3 - Panic while idle changes nothing (Priority: P2)

**Acceptance Scenarios**:

1. **Given** no keys held and no learn session, **When** panic runs, **Then** no action is performed, nothing is stored and only "MIDI reset" is announced.

### Edge Cases

- Panic with listening off: it still clears the (empty) state and announces; nothing is started.
- A blackout the user set with the Black out button (not by a hold) stays: a hold release restores only what the hold did (MIDI-006).
- Keys released by panic whose physical note-off arrives later: the late release is ignored (the key is already up).
- A key pressed again after panic but before its note-off: it is a new press.
- Panic during a learn on the MIDI Mappings screen: the status shows "MIDI reset." and learning ends.

## Requirements *(mandatory)*

### Functional Requirements

- **MIDI-013-R1**: Panic MUST put every held trigger key up and send a release for each one bound to a hold target, through the same path as a lost source.
- **MIDI-013-R2**: Panic MUST reset the shared press rule: no down keys, no last-press times, no same-batch presses.
- **MIDI-013-R3**: Panic MUST discard messages waiting in the input queue.
- **MIDI-013-R4**: Panic MUST cancel any learn session (CC, trigger or scene) with no binding.
- **MIDI-013-R5**: Panic MUST NOT change the stored mappings, the current scene or cue, live CC parameter values, listening or the connected inputs.
- **MIDI-013-R6**: Panic MUST announce "MIDI reset" on the `.midi` lane each time it runs.
- **MIDI-013-R7**: Settings' MIDI section MUST offer a "MIDI Panic" button with an accessibility hint; ⌘⇧M MUST run panic on the visualizer and in Settings; the visualizer MUST offer a VoiceOver custom action "MIDI panic".
- **MIDI-013-R8**: A trigger row "MIDI panic" (`midi.panic`, trigger mode only) MUST be learnable in MIDI Mappings and stored in the MIDI-006 line format; pressing its key runs panic.
- **MIDI-013-R9**: Panic while idle MUST perform no action and store nothing.
- **MIDI-013-R10**: The press-rule and router reset MUST be pure Swift and pass on Linux.

### Key Entities

- **Panic**: a one-shot command with no stored state.
- **Panic trigger binding**: a MIDI-006 trigger line whose action is `midi.panic`.

## Privacy review *(Constitution, Privacy)*

- Panic stores nothing and adds no UserDefaults key, network API or permission. A `midi.panic` binding is one more
  mapping line in the existing list.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MIDI-013-S1**: After panic, zero keys are held and the press rule holds nothing (the row's acceptance).
- **MIDI-013-S2**: A hold blackout is restored, learning is cancelled and the stored mappings are byte-identical after panic.
- **MIDI-013-S3**: A press after panic fires once.
- **MIDI-013-S4**: Panic while idle performs no action.
- **MIDI-013-S5**: A UI test holds a note, taps MIDI Panic and reads 0 held, in under 30 s.
- **MIDI-013-S6**: All repository checks pass and the package tests pass on the host (and Linux in CI).

## Assumptions

- Panic is local to the app: it sends nothing to MIDI devices (the app has no MIDI output).
- A physical controller check (a stuck pad cleared by the button) is the `{device}` task in the last stage.
