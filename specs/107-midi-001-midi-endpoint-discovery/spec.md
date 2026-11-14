# Feature Specification: MIDI-001 MIDI Endpoint Discovery

**Feature Branch**: `feature/midi-001` (spec directory `107-midi-001-midi-endpoint-discovery`)

**Created**: 2026-11-14

**Status**: Planned 2026-11-14 (analyze fixes applied)

**Input**: User description: "Implement MIDI-001 (MIDI endpoint discovery) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "List connected and virtual MIDI
endpoints without internet access." Acceptance, verbatim: "Mock endpoints appear and disappear with
stable IDs." Verification: unit tests with fake MIDI; a physical controller in the last stage.
Depends on MOD-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MIDI-001-R1…`, success criteria `MIDI-001-S1…`, tasks `MIDI-001-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `63867693`)

The row's gap status is "Gap candidate". The audit confirms a full gap.

| Area | Today |
|---|---|
| MIDI code | None. No source file imports the system MIDI framework; "MIDI" appears only in comments (PerformanceControl's package note, ParameterGraph's external-control policy from MOD-001-R4). |
| Where MIDI belongs | `Packages/PerformanceControl` already names "the show, modulation and MIDI rows" as its scope and hosts OSC-001's receiver: pure Swift lifecycle and model (Linux-testable), with the one platform transport in its own folder behind a protocol and a fake transport in tests. |
| External control target | MOD-001's parameter registry marks every registered parameter as settable by external control (MIDI, OSC); nothing uses that for MIDI yet (MIDI-003 will). |
| App pattern to follow | OSC-001: off by default (`settings.osc.enabled`), runs only while enabled and the app is in the foreground, a Settings section with toggle and status, status texts unit-tested, DEBUG stand-in transports for UI tests. |
| Network guard | FR-068 as amended (ADR-0008): no networking outside the OSC transport folder; `scripts/check_compliance.py` (source) and `scripts/check_network_symbols.py` (built binary, FILE-012) enforce it. Neither knows about network MIDI yet. |
| Permissions | FILE-013's `PermissionCatalog` lists every usage string; `scripts/check_permission_catalog.py` fails on an uncatalogued key. There is no Bluetooth usage string. |
| Stored keys | `scripts/run_device_tests.py` `ALLOWED_KEYS` lists every UserDefaults key the app may write (privacy review). |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which kinds of MIDI endpoints are listed? → A: Every source and destination the system's MIDI service reports on the device: hardware connected by USB (class-compliant controllers through a USB-C or Lightning adapter), virtual endpoints published by other apps on the same device, and Bluetooth MIDI devices that the system has already connected (the system lists them like any other endpoint; listing them asks for no permission). Network MIDI session endpoints are never listed (MIDI-001-R2). Rejected: listing only hardware (virtual endpoints are how other music apps on the device talk to each other, and the row names them).
- Q: Is network MIDI (MIDI over the local network) enabled? → A: No. The app never enables, configures or references the system's network MIDI session, and a network-session endpoint that appears anyway is hidden (MIDI-001-R2). The constitution allows networking only for the OSC receiver's one folder (FR-068 amendment, ADR-0008); network MIDI would be a second network listener with its own peer discovery and needs its own row and review. The source and binary scans are extended to fail on any network MIDI symbol (MIDI-001-R14). Recorded in a new ADR.
- Q: Does the app offer to pair Bluetooth MIDI devices? → A: Not in this row. Pairing needs the system's Bluetooth MIDI pairing screen, a Bluetooth usage string and a new permission request, which FILE-013's catalog and review would have to cover. Bluetooth devices the system already connected are listed (above). A pairing row can follow (recorded in the ADR as deferred).
- Q: What makes an endpoint's ID stable? → A: The system's unique ID for the endpoint, which the system keeps for a device across unplug and replug and which differs between two physical devices of the same model. When that number is missing (zero) or two current endpoints report the same number, a fallback ID is derived from the direction and the device, entity and endpoint names, with an ordinal when those collide too (MIDI-001-R4). The fallback's risk (two identical unnamed devices may swap fallback IDs after a replug) is documented; the system assigns unique IDs to every endpoint it creates, so the fallback is not expected in practice.
- Q: What is stored? → A: Only the "Listen for MIDI devices" toggle (`settings.midi.enabled`, off by default). No endpoint name, ID, count or history is stored, logged or sent; the list lives in memory while listening (MIDI-001-R10). Mappings that need stored IDs are MIDI-003/MIDI-012's and will decide their own persistence.
- Q: When does the app watch for MIDI devices? → A: Only while the toggle is on and the app is active in the foreground, like OSC-001. Turning it off or leaving the foreground clears the list and stops reporting changes (MIDI-001-R7). No MIDI messages are received or parsed in this row (MIDI-002 onward).
- Q: Does the app create its own virtual MIDI endpoint? → A: No (no other app can talk to projectM in this row; MIDI-009 feedback may add an output).
- Q: Is there a badge on the visualizer like OSC's? → A: No. OSC's badge warns that a network listener is open; discovery opens no listener and receives nothing. The Settings section shows the status. MIDI-002's monitor may add one when messages are received.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rule 4 (recommended option first).

- Q: In what order are endpoints listed? → A: Inputs first, then outputs; within each, by display name (case-insensitive, locale-independent), then by ID, so the order is the same on every refresh and in tests (MIDI-001-R9). Rejected: system order (it changes with plug order).
- Q: Is the first list after turning listening on (or returning to the foreground) announced device by device? → A: No. Only changes after the first list are announced; the first list sets the baseline silently, and the status line ("Listening — N devices") states the count (MIDI-001-R11). Otherwise every return to the foreground would read out every device.
- Q: What happens when the system MIDI service cannot be started? → A: The status shows "MIDI isn't available on this device." with no automatic retry; turning the toggle off and on tries again (MIDI-001-R8), as OSC-001-R3 does for its listener.
- Q: Does an abnormal end of the previous session (PERF-010) turn MIDI listening off? → A: No. PERF-010 turns OSC off because it is a network listener; MIDI discovery receives nothing and opens nothing to the network, so the stored toggle is kept.
- Q: How are a rename and an online change of the same endpoint in one refresh reported? → A: As two changes, renamed first then online changed, both naming the same ID; appeared and disappeared exclude any other change for that endpoint (MIDI-001-R5).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I see my MIDI controller when I plug it in (Priority: P1)

A performer turns on "Listen for MIDI devices" in Settings and plugs a USB MIDI controller into the
iPad. Its input and output appear in the MIDI section within a moment, named as the device names
itself. Unplugging it removes it; plugging it back shows it again as the same device.

**Why this priority**: It is the row's acceptance criterion and the base for MIDI learn and mappings.

**Independent Test**: With a fake MIDI system, add endpoints, remove them, add them back: the list
follows, and each endpoint has the same ID after the replug.

**Acceptance Scenarios**:

1. **Given** listening is on and no device is connected, **When** a device with one input and one output appears, **Then** both are listed with their names, direction and "connected" status, and one change is reported for each.
2. **Given** the device is listed, **When** it disappears, **Then** both entries leave the list and a disappeared change is reported for each.
3. **Given** the device was unplugged, **When** the same device appears again, **Then** its entries carry the same IDs as before.
4. **Given** two identical controllers (same model and names) are connected, **When** the list is shown, **Then** each has its own ID and the names are told apart on screen.
5. **Given** listening is on, **When** a device appears, **Then** VoiceOver users hear one short announcement naming it.

---

### User Story 2 - I see music apps on the same device (Priority: P2)

A performer runs a synth or sequencer app that publishes a virtual MIDI output. projectM lists it,
marked as virtual, next to hardware.

**Why this priority**: Virtual endpoints are the row's second named kind.

**Independent Test**: The fake adds an endpoint with no device behind it: it is listed and marked virtual.

**Acceptance Scenarios**:

1. **Given** listening is on, **When** another app publishes a virtual source, **Then** it is listed as a virtual input.
2. **Given** a listed endpoint, **When** its name changes, **Then** the entry keeps its ID and shows the new name (a renamed change).
3. **Given** a listed device that goes offline but stays known to the system, **When** the list is shown, **Then** it is marked offline, keeps its ID, and becomes connected again when it returns.

---

### User Story 3 - Nothing happens until I ask, and nothing leaves the device (Priority: P1)

A user who never uses MIDI sees no change: MIDI is off by default, nothing is watched, nothing is
stored, and the app gains no network ability.

**Why this priority**: Privacy and the constitution's networking rule.

**Independent Test**: Fresh install: the toggle is off and the list is empty; the built app passes
the network symbol scan; the stored keys are only the toggle.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** Settings opens, **Then** "Listen for MIDI devices" is off and no endpoints are shown.
2. **Given** listening is on, **When** the app leaves the foreground or the toggle is turned off, **Then** the list is cleared and no further changes are reported.
3. **Given** the built app, **When** it is scanned, **Then** it contains no network MIDI and no other forbidden network symbol.

### Edge Cases

- A burst of system changes (a hub with several devices plugged in at once) produces one refresh, not one per notification.
- An endpoint present but offline: listed as offline, not removed.
- An endpoint whose unique ID is zero, or two endpoints with the same unique ID: fallback IDs, still distinct.
- An endpoint with no display name: shown as "MIDI device" (input or output), never blank.
- Rename while offline: one renamed change and one online change, same ID.
- Toggle turned off during a pending refresh: the refresh does nothing.
- The MIDI service cannot be started (system error): the status says MIDI isn't available; nothing retries in a loop.
- A network MIDI session endpoint reported by the system: hidden.
- Platforms without a MIDI service (Linux CI): the pure model and diffing build and test; discovery reports "unavailable".

## Requirements *(mandatory)*

### Functional Requirements

- **MIDI-001-R1**: The app MUST list every MIDI source (shown as input) and destination (shown as output) the system reports, with display name, direction, connected or offline status, and whether it is virtual (no device behind it) or external.
- **MIDI-001-R2**: The app MUST NOT enable, configure or reference the system's network MIDI session, and MUST hide any endpoint the system attributes to network MIDI. It MUST NOT show the Bluetooth pairing screen or request Bluetooth permission.
- **MIDI-001-R3**: Each endpoint MUST have an ID that is unique within the current list and stable across unplug and replug of the same device, renames and online changes.
- **MIDI-001-R4**: The ID MUST come from the system's unique endpoint number when it is non-zero and not shared by another current endpoint; otherwise from a fallback derived from direction, device, entity and endpoint names, with an ordinal for identical fallbacks in list order. The kind of ID (system or fallback) MUST be visible to tests.
- **MIDI-001-R5**: Changes between two lists MUST be reported as appeared, disappeared, renamed and online-changed, one change per endpoint and kind, in a deterministic order (disappeared, then appeared, then renamed, then online changed, each in list order; renamed before online changed for the same endpoint); an endpoint that appeared or disappeared has no other change; an unchanged list reports nothing.
- **MIDI-001-R6**: System change notifications MUST be coalesced: the first notification in a quiet period schedules one refresh after a short delay (100 ms); notifications before that refresh starts add nothing; a notification during or after it schedules the next one.
- **MIDI-001-R7**: Discovery MUST run only while the user's toggle is on and the app is active in the foreground; turning off or leaving the foreground MUST clear the list, cancel a pending refresh and stop reporting changes; returning restarts discovery with a fresh list.
- **MIDI-001-R8**: The toggle MUST be off by default and stored as one boolean; Settings MUST show a MIDI section with the toggle, a status line ("Off", "Listening — no MIDI devices", "Listening — N devices", or the unavailable text "MIDI isn't available on this device.", with no automatic retry) and the endpoint rows.
- **MIDI-001-R9**: Each row MUST show the name (with " (2)", " (3)"… appended when two endpoints in the same direction share a name), "Input" or "Output", and "Virtual" and "Offline" where they apply; VoiceOver reads one combined label per row. Rows are ordered inputs first, then outputs, each by display name (case-insensitive), then ID.
- **MIDI-001-R10**: Endpoint names, IDs and counts MUST NOT be stored, logged or sent; only the toggle is stored.
- **MIDI-001-R11**: Appearances and disappearances MUST be announced to VoiceOver through the shared announcer (ACC-004/ACC-011), one announcement per refresh, never for the first list after listening starts: "MIDI device connected: <name>", "MIDI device disconnected: <name>", or "<n> MIDI devices connected/disconnected" for more than one; both sentences joined when one refresh has both. Endpoints of one device count as one device, named by the device name (a virtual endpoint by its own name). Never a direct post.
- **MIDI-001-R12**: Discovery MUST NOT receive or parse MIDI messages and MUST NOT allocate per MIDI message (none are subscribed in this row); refreshes run off the main thread and the app copies results onto the main actor.
- **MIDI-001-R13**: The pure endpoint model, ID rule, diffing and coalescing MUST build and pass their tests on Linux; the system implementation compiles only where the system MIDI framework exists, and elsewhere discovery reports unavailable.
- **MIDI-001-R14**: The source compliance check and the binary network symbol scan MUST fail on network MIDI symbols, and the built app MUST pass both.
- **MIDI-001-R15**: A stand-in MIDI system selected by the DEBUG-only launch argument `-uitestFakeMIDI` MUST let UI tests plug and unplug a fake device from Settings. The launch argument handling and the Plug/Unplug panel compile only in DEBUG; the scripted provider itself is an ordinary package type (also used by the package tests) that a Release build never instantiates.

### Key Entities

- **MIDI endpoint**: ID (system or fallback), direction (input/output), display name, device/entity/endpoint names (for the fallback only), connected or offline, virtual or external, transport attribution (USB/other, Bluetooth, network: hidden).
- **Endpoint change**: appeared, disappeared, renamed (old and new name), online changed (new status); each names the endpoint ID.
- **Discovery state**: off, listening (with list), unavailable (system error code only).
- **MIDI toggle**: one stored boolean, off by default.

## Privacy review *(Constitution, Privacy)*

- Nothing about MIDI devices is stored, logged, exported in diagnostics, or sent: only the toggle persists (MIDI-001-R10). Device names are shown and spoken while listening and dropped when listening stops.
- No permission is requested; USB, virtual and already-connected Bluetooth endpoints need none.
- No network ability is added (MIDI-001-R2, R14). No messages are received in this row.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MIDI-001-S1**: With a fake MIDI system, endpoints that appear are listed and those that disappear leave the list, and every replugged endpoint carries the same ID as before (the row's acceptance).
- **MIDI-001-S2**: Two endpoints with identical names get distinct IDs and distinct on-screen names; a rename keeps the ID.
- **MIDI-001-S3**: Ten system notifications inside one coalescing delay produce exactly one refresh.
- **MIDI-001-S4**: Offline and online changes keep the ID and are reported once each.
- **MIDI-001-S5**: The diffing table (appeared, disappeared, renamed, online, renamed and online, unchanged) gives exactly the expected changes.
- **MIDI-001-S6**: A UI test plugs a fake device in Settings and sees it listed, unplugs it and sees it leave, in under 30 s.
- **MIDI-001-S7**: The built app passes the network symbol scan and the privacy manifest check; the compliance, permission catalog, status events and motion policy checks pass.
- **MIDI-001-S8** `{device}`: On a physical device with a USB MIDI controller, the controller appears within 1 s of plugging in, leaves on unplug, and returns with the same ID.

## Assumptions

- The system keeps an endpoint's unique number across replug of the same device (documented system behaviour for saved MIDI setups); verified on a device in S8.
- A 100 ms coalescing delay is short enough to feel immediate and long enough to merge a hub's burst.
- MIDI-002 onward (monitor, learn, mappings, clock, hot-plug recovery) build on this list and its IDs and are out of scope.
