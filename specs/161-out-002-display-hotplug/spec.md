# Feature Specification: OUT-002 Display Connect Handling

**Feature Branch**: `feature/out-002` (spec directory `161-out-002-display-hotplug`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement OUT-002 (Display connect handling) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Start or stop external output on
hot-plug without losing scene state." Acceptance, verbatim: "Connect/disconnect fixture leaves
internal render session active." P1, M, depends on OUT-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `OUT-002-R1…`, success criteria `OUT-002-S1…`, tasks `OUT-002-T01…`. Requirements of
other features are cited by their own IDs: OUT-001-R1 to R11 (external display scene), OUT-010
(output blackout), REC-003-R11 (a recording stops when the picture size changes), FX-009-R5 (trails
reset triggers), FX-019-R11 (flash history survives moves), ACC-004 and ACC-011 (announcements and
captioned status events), PERF-011 (presentation loss).

## Baseline: what exists today (audit of 2026-11-14, commit `0d19488e`)

| Area | Today | Gap for this row |
|---|---|---|
| Connection | OUT-001: an external display reaches `ExternalDisplayCoordinator` from three places (the iOS 26 scene delegate, the iOS 27 scene accessory, the DEBUG fake). Connect, resize, foreground and disconnect go into the pure `ExternalDisplayRouting`; `place()` moves the one visual view into the target slot inside the call. | No common seam for a test to inject hot-plug events with a fake display; the coordinator talks to concrete callers. |
| Internal session | Moving the view does not recreate the renderer, compositor, engine, preset, scene or audio source (OUT-001-R4). The renderer's display link stops and starts with the window change; the instance and its counters continue. | Not proved by a connect/disconnect fixture with a running session; no counter of what the external side holds. |
| Quick connect/disconnect | Every connect moves the visual at once, every disconnect moves it back. A flapping cable or AirPlay reconnect moves the visual back and forth, and every move changes the drawable size, which resets FX-009 trails (FX-009-R5). | No debounce. |
| Recording | REC-003-R11: a recording stops when the picture size changes; OUT-001's move changes it, so plugging in a display ends the recording. | Hot-plug interrupts a recording. |
| Blackout | OUT-010: `place()` covers every slot before moving the visual, so a new external slot is black while blacked out. | Not tested for a slot that connects while blacked out. |
| Announcements | Blackout is announced (X21-X23); connection changes are logged only. | No "External display connected/disconnected" announcement. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: Does connecting a display mirror the composite or move the output? → A: Follow OUT-001: the one visualization moves to the external display (no second render, no device preview, OUT-001-R3). The internal render session (visual host, renderer or compositor, engine, preset, scene, audio source) is never created, recreated, paused or re-applied by a connect or a disconnect; only its view changes window (OUT-002-R1).
- Q: What does "debounce" mean for quick connect/disconnect? → A: A connect settles for 0.3 s before the visual moves; a disconnect within that time cancels it and nothing moves, nothing is announced. A disconnect is always applied at once (its window is going away). 0.3 s stays inside OUT-001-R6's 0.5 s. Rejected: delaying disconnects (the visual would sit in a dying window); no debounce (a flapping connection moves the visual and resets trails on every bounce) (OUT-002-R3).
- Q: What happens to an active recording when a display connects or disconnects? → A: While a recording runs, the visual stays where the recording started: a display that connects stays black (blackout state applied) and receives the visual when the recording ends; a display that connects and disconnects during the recording never moves it. So the recording continues uninterrupted (REC-003-R11 never triggers). Only if the display that the recording is on is unplugged does the visual have to come back to the device (the window is gone); the recording then stops with REC-003's size-change notice and keeps what was recorded. Rejected: moving anyway (ends the recording, the current behaviour); scaling frames of the new size into the recording (a new shader path in the compositor and the spectrum host, letterboxed video) (OUT-002-R4).
- Q: Do FX-009 trails reset on hot-plug? → A: Only when the visual's output size actually changes (FX-009-R5 unchanged). A connect that is cancelled by the debounce, or held by a recording, changes no size and resets nothing. Hot-plug itself never calls the scene-change reset (OUT-002-R2).
- Q: Which blackout state does a newly connected display get? → A: The current one: a display connecting while blacked out (or restoring) shows black from its first frame; nothing about the blackout changes (OUT-002-R5).
- Q: How are connection changes announced? → A: Through ACC-011's status-event router as system rows on a new `display` announcer lane (so a connection never delays or replaces a blackout announcement on the `output` lane): X27 "External display connected" (with "It shows the visualization when the recording ends." while a recording holds the visual) and X28 "External display disconnected", each with a transient caption. Only settled connects and disconnects of settled displays are announced; system rows are dropped while the app is not active (ACC-011-R10) (OUT-002-R6).
- Q: How are hot-plug events injected in tests? → A: A protocol (`ExternalDisplayEventSink`) is the one seam: the scene delegate, the iOS 27 accessory, the DEBUG fake display and the unit tests' fake connector all drive the coordinator through it; the coordinator's settle timer and clock are injected (OUT-002-R7).

- Q (clarify pass): What does the device show while a connection settles or is held by a recording? → A: The visualization, unchanged; the external display is black. The device's "Showing on external display" note appears only when the visual has actually moved (it follows where the visual is, not which displays are connected). Rejected: showing the note at connect (it would claim a move that has not happened) (OUT-002-R3, R4).
- Q (clarify pass): Can the settle time or the recording hold be changed by the user? → A: No: a fixed 0.3 s and an automatic hold, no new setting and no stored data (OUT-002-R9). Rejected: a "move output during recording" option (a choice nobody needs before REC-016's resume-in-file exists).
- Q (clarify pass): How is hot-plug observed when diagnosing? → A: The coordinator logs connect, settle, cancel and hold decisions under the existing `ExternalDisplay` log category (no user data), and keeps counters (moves, cancelled connections, slots, pending connections) read by tests and a DEBUG UI-test probe (OUT-002-R8).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Plug and unplug without losing the show (Priority: P1)

A performer has a scene running (a visual, a preset, parameters, effects). They plug in a projector:
the visualization appears on it. They unplug it: the visualization is back on the device. Nothing
restarts: the same preset, scene and parameters keep going, the audio never stops, and only the
picture size change (if any) clears the trails.

**Why this priority**: It is the row's observable behaviour and acceptance.

**Independent Test**: A unit fixture with a fake display connector and a running render session
injects connect, disconnect, connect, disconnect and checks the session is the same instance, still
counting frames, with unchanged scene state.

**Acceptance Scenarios**:

1. **Given** the visualizer running with a scene applied, **When** a display connects and settles, **Then** the visual moves to it and the render session, preset, scene and parameters are unchanged.
2. **Given** the visual on the external display, **When** the display disconnects, **Then** the visual is back on the device in the same call, and nothing the external display held remains.
3. **Given** a recording running on the device, **When** a display connects and later disconnects, **Then** the recording continues uninterrupted and the visual never moves.

### User Story 2 - A flaky connection does not thrash (Priority: P2)

An AirPlay or cable connection drops and returns several times within a second. The visual does not
jump back and forth and nothing is announced for connections that did not last.

**Independent Test**: Inject connect then disconnect within the settle time, 20 times; the visual
never moves, nothing is announced, and nothing is left held.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** a display connects and disconnects within 0.3 s, **Then** the visual never leaves the device and no announcement is made.
2. **Given** 20 connect/disconnect cycles, **When** they end, **Then** no slot, pending connection or observer remains and every external slot is released.

### User Story 3 - Blackout and announcements follow the new display (Priority: P2)

With the output blacked out, the performer plugs in a projector: it stays black. VoiceOver users hear
"External display connected" and "External display disconnected".

**Acceptance Scenarios**:

1. **Given** the output blacked out, **When** a display connects, **Then** it is black from its first frame and the blackout state is unchanged.
2. **Given** the app active, **When** a display connection settles or a settled display leaves, **Then** the matching announcement and caption are posted once.

### Edge Cases

- A display connects while no visualization runs: it stays black (OUT-001); its connection is still announced.
- The display a recording is on is unplugged: the visual must return to the device; the recording stops with REC-003's size-change notice and keeps what was recorded (the only unavoidable interruption).
- A recording ends while a display is connected: the visual moves to it then (OUT-001 routing).
- A size or foreground change of a display still settling updates what it will settle with.
- Two displays: OUT-001's rule (the first eligible keeps the visual) is unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-002-R1**: Connecting, disconnecting or reconnecting an external display MUST NOT create, recreate, pause, restart or re-apply the internal render session (visual host, renderer or compositor, engine), the scene, the preset, the parameters or the audio source.
- **OUT-002-R2**: Hot-plug MUST NOT trigger a trails reset of its own; trails reset only when the visual's output size changes (FX-009-R5).
- **OUT-002-R3**: In the app, a connect MUST settle for 0.3 s before the visual moves (unit tests of OUT-001's in-call rules construct the coordinator with a settle time of 0); a disconnect during that time MUST cancel it with no move and no announcement; a disconnect of a settled display MUST be applied at once.
- **OUT-002-R4**: While a recording runs, a connect or disconnect MUST NOT move the visual unless the slot holding it is gone; when the recording ends, the visual MUST be placed by OUT-001's rules.
- **OUT-002-R5**: A newly connected display MUST show the current blackout state from its first frame.
- **OUT-002-R6**: Settled connections and disconnections MUST be announced through the status-event router ("External display connected", "External display disconnected"), on their own lane.
- **OUT-002-R7**: Connection events MUST reach the coordinator through one protocol, so tests inject them with a fake connector and an injected settle timer and clock.
- **OUT-002-R8**: After a disconnect, the coordinator MUST hold nothing of that display (slot, pending connection, geometry observer), and repeated cycles MUST NOT leak.
- **OUT-002-R9**: Public APIs only (Constitution I); builds for iOS 26 and 27; no new stored data.

### Key Entities

- **Pending connection**: a display that connected but has not settled: its slot (weak), geometry, foreground state and deadline.
- **Placement hold**: the target the visual stays on while a recording runs.
- **External resource counts**: slots, pending connections and slots holding the visual (tests, DEBUG probe).

## Success Criteria *(mandatory)*

- **OUT-002-S1**: The acceptance fixture (connect, disconnect, connect, disconnect with a running session, a scene applied and a recording) ends with the same session instance still counting frames, unchanged scene state, no trails reset, zero external resources and the recording still running.
- **OUT-002-S2**: 20 quick connect/disconnect cycles move the visual 0 times, announce nothing and release every slot.
- **OUT-002-S3**: A display connecting while blacked out is black before the connection call returns.
- **OUT-002-S4**: The existing OUT-001 and OUT-010 tests still pass.

## Assumptions

- The simulator cannot hot-plug reliably; the DEBUG fake display and unit fakes stand in. Physical hot-plug on D1-D3 is a `{device}` task.
- Settle time 0.3 s is a constant (no setting).
