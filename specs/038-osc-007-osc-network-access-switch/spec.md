# Feature Specification: OSC-007 OSC Network Access Switch

**Feature Branch**: `feature/osc-007` (spec directory `038-osc-007-osc-network-access-switch`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement roadmap row OSC-007 (OSC network access switch) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Default network control off
with visible listener status and stop." Acceptance, verbatim: "Fresh install opens no listener;
toggle on/off changes socket state." P0, effort S, depends on OSC-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `OSC-007-R1…`, success criteria `OSC-007-S1…`, tasks `OSC-007-T01…`. FR-068 as
amended on 2026-11-12 (ADR-0008, "Owner ruling: networking for OSC") and every OSC-001 requirement
(`specs/032-osc-001-osc-receiver/spec.md`) stay in force.

## Baseline: what exists today (audit of 2026-11-13, commit `94f0192`)

OSC-001 already shipped most of the switch. The audit maps each part of the row to existing code
and tests; only the gaps are in scope.

| Part of the row | Today (code, test) | Gap |
|---|---|---|
| Default off | `settings.osc.enabled` absent → off (`AppSettings`); `SettingsTests.testOSCReceiverDefaultsPersistAndReadSafely` | none |
| Fresh install opens no listener (at launch) | `OSCReceiverCoordinatorTests.testOffByDefaultOpensNothing`: a coordinator on empty settings asks its transport for nothing | covered at construction only |
| Fresh install opens no listener (after the app leaves and returns to the foreground) | not tested | **gap**: foreground return must not open a listener while off |
| Toggle on/off changes socket state | package: `OSCLoopbackIntegrationTests.testFloatPacketUpdatesTestValueAndDisableClosesListener` (real UDP listener on loopback: ready, packet applied, stop → `off` only after the listener is cancelled, same port binds again). App: `OSCReceiverCoordinatorTests.testListensOnlyWhileEnabledAndActive` with a fake transport. | **gap**: no test drives the app's toggle (`setEnabled`) against the real system transport |
| Visible listener status | Settings footer "Off" / "Starting…" / "Listening on port N" / failure text; `OSCReceiverUITests` | **gap**: visible only inside Settings; nothing on the visualizer says a port is open |
| Stop | the Settings toggle | **gap**: no stop control where the status would be seen |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where is the listener status shown outside Settings? → A: A small "OSC listening on port N" badge on the visualizer, at the top, shown with or without the controls and never hidden by the controls' hide timer (OSC-007-R2). It shares the top status area with CAM-012's "Camera on" badge (built in parallel); the two are separate views stacked in one place, so neither covers the other (OSC-007-R6).
- Q: What drives the badge: the toggle or the listener? → A: The listener. The badge is shown only while the receiver reports `listening`, which follows the system's "ready" for the socket; it is not shown while starting, stopping, off, paused in the background, or after a failure (the failure stays explained in Settings, OSC-001-R16) (OSC-007-R2, R3).
- Q: What does Stop do? → A: A "Stop" button on the badge turns the OSC receiver setting off (the same stored setting as the Settings toggle, so Settings then shows the toggle off) and closes the listener the same way the toggle does: OSC-001's confirmed cancel, "Off" only after the system confirms (OSC-007-R4). It does not wait on the main thread. Turning OSC back on is only possible in Settings (no "start" on the visualizer: enabling network access is a deliberate choice made where the port and the explanation are).
- Q: Is a confirmation asked before Stop? → A: No. Stopping can only reduce network exposure and is undone from Settings; one tap is the point of a stop control.
- Q: Does Stop or the badge change anything else? → A: No. It never touches the audio source, the visual, the port or the test value; it writes only the existing `settings.osc.enabled` key (OSC-007-R5). No new stored key.
- Q: What does VoiceOver get? → A: The badge is one element labelled "OSC listening" with the value "Port N"; the Stop button is labelled "Stop OSC" with the hint "Turns off the OSC receiver". After Stop, VoiceOver announces "OSC off" (OSC-007-R7).
- Q: How is "toggle on/off changes socket state" proved in the app? → A: An app unit test on the simulator drives the coordinator's toggle against the real system UDP transport on a free high port: on → the state becomes `listening` (the system reported the socket ready); off → `off` (reported only after the system confirmed the cancel); then an independent second listener binds the same port, proving the socket was released. If the sandbox refuses the port, the test is skipped, never passed (OSC-007-S2).
- Q: Is an ADR needed? → A: No. No default is overridden; this row adds a status badge and a stop control on top of OSC-001's switch, inside ADR-0008's ruling.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See that OSC is listening (Priority: P1)

A performer turned on "OSC receiver" in Settings earlier. Back on the visualizer, with the controls
hidden, a small badge "OSC · port 9000" at the top tells them the app is listening on the network.

**Why this priority**: Network access must never be invisible; this is the "visible listener
status" half of the row.

**Independent Test**: Enable OSC in Settings, close Settings, hide the controls: the badge with the
port is shown; turn OSC off in Settings: the badge is gone.

**Acceptance Scenarios**:

1. **Given** OSC is on and the listener is ready on port N, **When** the visualizer is shown (controls shown or hidden), **Then** the badge reads "OSC · port N".
2. **Given** OSC is off (fresh install or turned off), **When** the visualizer is shown, **Then** no badge is shown.
3. **Given** OSC is on but the port could not be opened (in use, permission denied), **When** the visualizer is shown, **Then** no badge is shown and Settings explains the failure.

---

### User Story 2 - Stop OSC with one tap (Priority: P1)

The performer wants the network closed now. They tap "Stop" on the badge. The badge disappears,
the listener is closed, and Settings shows the toggle off.

**Why this priority**: The "stop" half of the row and the privacy control for network access.

**Independent Test**: With OSC listening, tap Stop: the badge disappears and the Settings toggle is
off with status "Off".

**Acceptance Scenarios**:

1. **Given** the badge is shown, **When** the user taps Stop, **Then** the setting is turned off, the listener is cancelled, the badge disappears, and Settings shows the toggle off with "Off".
2. **Given** OSC was stopped from the badge, **When** the app leaves and returns to the foreground or is relaunched, **Then** no listener opens.
3. **Given** audio is playing, **When** the user taps Stop, **Then** audio and the visual are unaffected.

---

### User Story 3 - A fresh install never opens a socket (Priority: P1)

A new user installs the app and uses it, including switching away and back. No network listener
ever opens until they turn OSC on.

**Why this priority**: The first half of the acceptance criterion.

**Independent Test**: With no stored settings, launch, leave the foreground, return: the transport
is never asked to open.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** the app launches, **Then** no listener is opened.
2. **Given** a fresh install, **When** the app leaves and returns to the foreground, **Then** no listener is opened.

### Edge Cases

- Stop tapped twice quickly: the second tap does nothing (the badge is already gone; turning off an off receiver changes nothing).
- Stop tapped while the controls are hidden: the badge's button works without showing the controls first.
- The app leaves the foreground while listening: the badge disappears with the listener (OSC-001-R3) and returns when the listener is ready again; the setting stays on.
- The port changes in Settings while listening: the badge shows the new port only once the new listener is ready.
- CAM-012's camera badge is shown at the same time: both badges are visible, stacked, neither covers the other.

## Requirements *(mandatory)*

### Functional Requirements

- **OSC-007-R1**: A fresh install (no stored OSC setting) MUST open no network listener at launch, nor when the app leaves and returns to the foreground (restates OSC-001-R1 as this row's acceptance; tested here for the foreground return).
- **OSC-007-R2**: While the OSC receiver reports that its listener is ready, the visualizer MUST show a badge naming the port ("OSC · port N"), whether or not the controls are shown; the controls' hide timer MUST NOT hide it.
- **OSC-007-R3**: The badge MUST NOT be shown in any other receiver state (off, starting, stopping, failed, paused in the background).
- **OSC-007-R4**: The badge MUST offer a "Stop" button that turns the OSC receiver setting off and closes the listener with OSC-001's confirmed cancel; afterwards Settings MUST show the toggle off.
- **OSC-007-R5**: Stop MUST NOT change the audio source, the visual, the port or the test value, and MUST NOT add a stored key.
- **OSC-007-R6**: The badge MUST share the visualizer's top status area with other status badges (CAM-012's camera badge) without covering them or the controls.
- **OSC-007-R7**: The badge MUST be accessible: one element labelled "OSC listening" with the value "Port N"; the Stop button labelled "Stop OSC" with a hint; "OSC off" announced after Stop.
- **OSC-007-R8**: Turning OSC on and off with the app's switch MUST move the real system listener between ready and cancelled, and the port MUST be free again after off.

### Key Entities

- **OSC listener badge**: derived only from the receiver state; present with a port while the state is `listening(port)`, absent otherwise. Holds no state of its own.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **OSC-007-S1**: With no stored settings, launching and one background-foreground cycle ask the transport to open 0 times (unit test).
- **OSC-007-S2**: Toggling on then off with the real system transport reaches "listening" then "off", and a second listener binds the same port afterwards (simulator unit test; skipped, not passed, if the sandbox refuses the port).
- **OSC-007-S3**: For every receiver state, the badge is present exactly for `listening(port)`, with that port (unit test over all states).
- **OSC-007-S4**: On the simulator, enabling OSC shows the badge with the chosen port; one tap on Stop removes it, and Settings shows the toggle off and "Off" (UI test, under 30 s).
- **OSC-007-S5** `{device}`: On D1 over Wi-Fi, the badge is shown while a controller can reach the app and Stop ends delivery (last stage, owner).

## Out of scope

- Peer allowlist (OSC-008), rate limiting (OSC-009), discovery (OSC-011), sending (OSC-005).
- Starting OSC from the visualizer.
- Showing failures on the visualizer (Settings keeps the explanation).

## Assumptions

- OSC-001's receiver states and confirmed cancel are correct (tested there); this row builds on them.
- The simulator can open a loopback UDP listener (OSC-001 measured it); if not, OSC-007-S2 is skipped and reported as not verified.
- CAM-012 merges into the same top area of the visualizer; the merge point is the visualizer's top status stack.
