# Feature Specification: MIDI-003 MIDI Learn

**Feature Branch**: `feature/midi-003` (spec directory `128-midi-003-midi-learn`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MIDI-003 (MIDI learn) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Bind the next eligible incoming control to a selected parameter."
Acceptance, verbatim: "One CC message creates one binding and exits learn mode." Verification: unit
tests with fake MIDI; a physical controller in the last stage. Depends on MIDI-001 and MOD-001
(integrated); MIDI-002's input and message model are integrated."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MIDI-003-R1…`, success criteria `MIDI-003-S1…`, tasks `MIDI-003-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `d0f2ef49`)

The row's gap status is "Gap candidate". The audit confirms a full gap: nothing binds a MIDI control
to anything.

| Area | Today |
|---|---|
| MIDI messages | MIDI-002: `MIDIEvent` (no source field) with `controlKey` (kind, channel, number; notes keyed as note on) and `normalizedValue`; `MIDIInputCoordinator` delivers batches at up to 30 Hz to registered clients while "Listen for MIDI devices" is on and the app is in the foreground. DEBUG `-uitestFakeMIDI` sends one CC (channel 1, controller 7, value 100) and one note from the MIDI Monitor. |
| Endpoint IDs | MIDI-001: stable IDs from the system's unique number; a name-based fallback ID is marked so later rows can refuse to persist it (ADR-0038 Decision 4). |
| Parameters | MOD-001: `VisualParameterCatalog` registers 14 visual parameters; every one allows external control (`ModulationPolicy.allowsExternalControl`). Manual values live in the app's settings, not in a live parameter store. |
| What the app renders from parameters | MOD-002: audio bindings resolved per frame in `NativeSpectrumHost`; only the glow (bloom) is resolved there: `resolveEffectiveGlow` takes the manual glow, applies the bound intensity, then ACC-012's `SafetyClamp` (depth and intensity cap) before the bloom. Spectrum geometry is set through generator configurations, not resolved per frame. |
| OSC | OSC-001/002 write a fixed route table (one test address → one test parameter) into their own store; there is no binding storage model to reuse. |
| Undo | SCN-010's history records scene inputs (spectra options, glow settings, text, layer composites, video loop and speed). |
| Backup and erase | FILE-005 carries `LibrarySettingsPolicy.includedKeys`; FILE-011's Settings category erases the included keys (minus those owned elsewhere) plus the device switches. |
| Announcements | `AccessibilityAnnouncer` kind `.midi` through the status-event router; `check_status_events.py` lists the MIDI files. |
| Later rows | MIDI-004 (scaling, curves, inversion), MIDI-005 (14-bit pairs), MIDI-006 (note triggers), MIDI-008 (transport buttons), MIDI-009 (feedback), MIDI-012 (profiles, export) build on the bindings this row creates. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Which parameters can be learned? → A: The registered visual parameters that allow external control, hold a continuous value and are applied by the app's per-frame resolution: the four glow parameters (Intensity, Radius, Threshold, Knee). Discrete, boolean and enum parameters wait for MIDI-006 (triggers) and spectrum geometry waits until a row resolves it per frame; offering a parameter that a control would not visibly drive would be a false promise.
- Q: Which incoming messages are eligible to learn? → A: Control change on controllers 0–119 only (the roadmap acceptance names CC). Notes, pitch bend, pressure, program change, system exclusive, clock, active sensing, transport and system common messages are ignored while learning, as are the channel mode controllers 120–127 (all sound off, reset all controllers, local control, all notes off, omni and mono/poly), which are commands, not knobs. The binding model keeps the message kind so MIDI-006 can learn notes later.
- Q: What identifies "the control" in a binding? → A: Message kind, MIDI channel and controller number, from any connected device. Not the sending device: MIDI-002 keeps no source on messages by design (ADR-0038 Decision 7), MIDI-001's fallback IDs are not stable across reconnects, and a stored device identifier would let the app's data fingerprint the user's equipment. Two devices sending the same channel and controller drive the same binding; per-device profiles are MIDI-012's.
- Q: What happens when several eligible messages arrive in one update? → A: Only the first eligible message (in arrival order) creates a binding; learn mode ends with it and every later message in that update is handled as normal traffic (never a second binding).
- Q: What if the control or the parameter is already bound? → A: Replace. A control drives at most one parameter and a parameter is driven by at most one control. Learning a control already bound to another parameter moves it (the old binding is removed) and the status says so; learning a parameter that already has a control replaces that control. No confirmation dialog: learn is used with one hand on the controller, and the change can be undone.
- Q: How do values reach the parameter? → A: A bound control's value (0–127, linear over the parameter's full range for now; curves and ranges are MIDI-004) sets the parameter's live value, which then passes through audio modulation and the sensory safety clamp before anything renders, exactly as a manual value would. The message that created a binding only creates it; values apply from the next message.
- Q: Are values stored or undoable? → A: No. Live values are not written to settings, not saved in scenes and not undoable per message (a controller sends dozens per second). Deleting a binding returns the parameter to its manual value at once.
- Q: Where are bindings stored? → A: Globally on the device (one mapping list for the app), not per scene: a controller rig stays the same while scenes change, and recalling a scene must not rebind the controller. They are included in the library backup and erased with the Settings category.
- Q: Is creating a binding undoable? → A: Yes, but in the MIDI Mappings screen, not in the scene history: an "Undo" action reverses the last mapping change (a learn or a delete) while the screen is open. Bindings are not scene state, so putting them in SCN-010's history would let a scene undo silently change the controller setup.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I map a knob to the glow by turning it (Priority: P1) — MVP

A performer turns on "Listen for MIDI devices", opens MIDI Mappings, taps "Learn" next to "Glow
intensity" and turns a knob. The row now shows "CC 7 · Ch 1", learn mode ends, and turning the knob
changes the glow.

**Why this priority**: It is the row's behaviour and acceptance.

**Independent Test**: With a fake MIDI system, start learning for a parameter and inject one control
change: exactly one binding exists for that channel and controller, learn mode is off, and another
control change creates nothing new.

**Acceptance Scenarios**:

1. **Given** listening is on and learn mode is active for Glow intensity, **When** one control change (channel 1, controller 7, value 100) arrives, **Then** exactly one binding (channel 1, controller 7 → Glow intensity) exists, learn mode is off, the status reads "Glow intensity mapped to CC 7 on channel 1." and VoiceOver announces it.
2. **Given** that binding, **When** a second control change (channel 1, controller 8) arrives, **Then** no binding is added.
3. **Given** learn mode is active, **When** one update holds three control changes on different controllers, **Then** only the first creates a binding.
4. **Given** the binding, **When** controller 7 sends 127 and then 0, **Then** the glow intensity's live value becomes the top and then the bottom of its range, and the stored manual setting is unchanged.

---

### User Story 2 - Learning never grabs the wrong message (Priority: P1)

While learning, clock, active sensing, notes and other messages keep arriving from the controller or
another app; none of them becomes a binding. The performer can cancel, and learning gives up on its
own if nothing is moved.

**Why this priority**: A wrong binding during a show is worse than none.

**Independent Test**: Inject every ineligible kind while learning: no binding; cancel: learn mode
off, no binding; let the timeout pass: learn mode off, no binding, a status says it timed out.

**Acceptance Scenarios**:

1. **Given** learn mode is active, **When** notes, pitch bend, pressure, program change, system exclusive, clock, active sensing, transport messages and controller 121 (reset all controllers) arrive, **Then** no binding is created and learn mode stays active.
2. **Given** learn mode is active, **When** the user taps Cancel, **Then** learn mode ends and nothing changes.
3. **Given** learn mode is active, **When** 30 seconds pass with no eligible message, **Then** learn mode ends, nothing changes, the status reads "MIDI learn timed out. Nothing was mapped." and VoiceOver announces it.
4. **Given** listening is off, **When** the mappings screen is shown, **Then** Learn is unavailable and the screen says "Turn on Listen for MIDI devices to learn a control."

---

### User Story 3 - I manage my mappings (Priority: P2)

The performer sees every mapping, deletes one, undoes a mistake, and moves a knob from one parameter
to another by learning again.

**Why this priority**: Mappings must be correctable without starting over.

**Independent Test**: Create bindings, re-learn a bound control for another parameter (it moves),
delete one, undo; relaunch: the mappings are still there; erase settings: they are gone.

**Acceptance Scenarios**:

1. **Given** CC 7 is mapped to Glow intensity, **When** the user learns Glow radius and turns CC 7, **Then** CC 7 drives Glow radius only, Glow intensity has no control, and the status says the control moved.
2. **Given** Glow intensity is mapped to CC 7, **When** the user learns Glow intensity again and turns CC 9, **Then** Glow intensity is driven by CC 9 only.
3. **Given** a mapping, **When** the user deletes it, **Then** the parameter returns to its manual value at once; **When** the user taps Undo, **Then** the mapping is back.
4. **Given** mappings exist, **When** the app relaunches, **Then** they are unchanged; **When** a library backup is made and restored, **Then** they come back; **When** Settings are erased, **Then** none is left.

---

### User Story 4 - Mapped values stay within my safety limits (Priority: P1)

A performer who chose the Strict sensory safety profile maps a knob to the glow intensity; turning it
fully up never exceeds the profile's intensity limit.

**Why this priority**: ACC-012 promises one clamp for everything that renders.

**Independent Test**: Under Strict, a bound control at 127 gives an effective glow intensity equal to
the profile's cap, not the range top.

**Acceptance Scenarios**:

1. **Given** the Strict profile and CC 7 mapped to Glow intensity, **When** CC 7 sends 127, **Then** the rendered intensity is at most the profile's intensity limit times the range top.

### Edge Cases

- A control change arrives for a binding whose parameter is no longer learnable (a stored mapping from a later version, or a damaged value): the entry is ignored and dropped on the next save; nothing crashes.
- Stored mapping text that cannot be read: ignored line by line; the rest load.
- Listening turned off, or the app sent to the background, while learning: learn mode ends at once without a binding (the status says why).
- The native visual is not shown (projectM or Camera): bindings still receive and hold the latest value; it applies when a native visual appears.
- Many messages per second from a mapped knob: only the newest value per parameter in each update is applied; nothing grows without bound.
- The same controller number on two channels: two different controls.
- Two devices on the same channel and controller: one control (no source is kept).
- Learn started twice, or for another parameter while learning: the newest request replaces the old one.

## Requirements *(mandatory)*

### Functional Requirements

- **MIDI-003-R1**: The app MUST offer learn mode for each learnable parameter: the registered parameters that allow external control (MOD-001), hold a continuous value and are applied by the per-frame resolution (this row: Glow intensity, radius, threshold, knee).
- **MIDI-003-R2**: While learn mode is active, the first eligible incoming message MUST create exactly one binding and end learn mode. Eligible: control change on controllers 0–119. Every other message is ignored for learning.
- **MIDI-003-R3**: When several eligible messages arrive together, only the first (arrival order) MUST create a binding.
- **MIDI-003-R4**: A binding MUST be identified by message kind, channel and controller number, and MUST NOT contain or be stored with any device or endpoint identifier, name or source.
- **MIDI-003-R5**: Rebinding MUST replace: a control drives at most one parameter and a parameter is driven by at most one control; moving a control removes its old binding and the status names the parameter it left.
- **MIDI-003-R6**: Learn mode MUST end without a binding on Cancel, after 30 seconds without an eligible message, when listening stops, or when the app leaves the foreground; a timeout is announced. Learn requires listening; while listening is off Learn is unavailable and the screen says why.
- **MIDI-003-R7**: Each later message on a bound control MUST set the parameter's live value linearly over its full range (value 0 → minimum, 127 → maximum); within one update the newest value per parameter wins. The message that created a binding does not set a value.
- **MIDI-003-R8**: Live values MUST pass through audio modulation (MOD-002) and the sensory safety clamp (ACC-012) before rendering, and MUST NOT change the stored manual setting, the scene, or the undo history. Deleting a binding returns its parameter to the manual value at once.
- **MIDI-003-R9**: Bindings MUST be stored on the device as one global list (not per scene), restored at launch, included in the library backup and removed by the Settings erase category. The stored form holds only kind, channel, controller number and parameter ID per binding. At most 64 bindings are kept.
- **MIDI-003-R10**: A "MIDI Mappings" screen, reached from the MIDI section of Settings, MUST list every learnable parameter with its control ("CC 7 · Ch 1" or "Not mapped"), a Learn action, a delete action for mapped rows, an Undo action for the last mapping change while the screen is open, and a status line ("Move a control on your MIDI device…" while learning, with Cancel).
- **MIDI-003-R11**: Starting learn mode, creating a binding and a timeout MUST be announced through the shared announcer (status events router), never posted directly; live values are never announced.
- **MIDI-003-R12**: The input MUST receive for mappings only while learn mode is active or at least one binding exists (and, as MIDI-002 requires, listening is on and the app is in the foreground).
- **MIDI-003-R13**: The learn and binding model MUST build and pass its tests on Linux.
- **MIDI-003-R14**: A DEBUG-only stand-in (`-uitestFakeMIDI`) MUST let a UI test send a control change from the mappings screen; Release builds never create it.
- **MIDI-003-R15**: The built app MUST still pass the network symbol scan, privacy manifest, compliance, permission catalog, motion policy and status events checks; no permission or usage string is added; the new stored key is on the device privacy allowlist.
- **MIDI-003-R16**: The binding model MUST leave room for MIDI-004 onward (range, curve, inversion, 14-bit, notes, profiles) without changing the stored form of existing bindings.

### Key Entities

- **Control key**: kind (control change in this row), channel 0–15, number 0–127 (learnable 0–119). From MIDI-002.
- **Binding**: control key → parameter ID. Stored as one text line per binding.
- **Mapping list**: ordered bindings, at most 64, one per control and one per parameter.
- **Learn session**: target parameter, deadline; outcome bound, moved, replaced, cancelled, timed out.
- **Live value**: latest value per bound parameter, in the parameter's units; memory only.

## Privacy review *(Constitution, Privacy)*

- A binding stores a channel, a controller number and a parameter ID; no device, endpoint, name or
  time. Two people's mapping lists cannot be told apart by equipment (MIDI-003-R4, R9).
- Received values live in memory only and are never logged, stored or announced.
- No permission or network ability is added (MIDI-003-R15).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MIDI-003-S1**: With learn mode active, one injected control change gives exactly one binding (its channel and controller → the selected parameter), learn mode off, and a second control change adds nothing (the row's acceptance).
- **MIDI-003-S2**: An update with several control changes gives exactly one binding; every ineligible kind leaves learn mode active and no binding.
- **MIDI-003-S3**: Cancel and a 30-second timeout end learn mode with no binding; the timeout is announced.
- **MIDI-003-S4**: Moving a bound control and re-learning a bound parameter each leave exactly one binding per control and per parameter.
- **MIDI-003-S5**: Control values 0 and 127 set the bound parameter to its minimum and maximum; under Strict, 127 on Glow intensity renders at most the profile's cap.
- **MIDI-003-S6**: Bindings survive a relaunch and a backup round trip, are removed by the Settings erase, and the stored form contains no endpoint identifier or name.
- **MIDI-003-S7**: A UI test with the stand-in MIDI system starts learning, sends a control change and sees the mapped row, in under 30 s.
- **MIDI-003-S8**: The built app passes the network symbol scan; compliance, permission catalog, status events, motion policy and docs checks pass.
- **MIDI-003-S9** `{device}`: On a physical device with a USB MIDI controller, learning a knob and turning it visibly drives the glow, and the mapping survives a relaunch.

## Assumptions

- Linear mapping over the full range is enough for this row; MIDI-004 adds ranges, curves and inversion per binding.
- 30 seconds is long enough to reach a controller and short enough that a forgotten learn mode does not grab a later move.
- 64 bindings exceed any learnable set this row offers and bound the stored list.
- The glow is the only parameter group resolved per frame today; more parameters become learnable as rows resolve them per frame.
