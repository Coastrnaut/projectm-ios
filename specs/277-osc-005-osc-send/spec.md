# Feature Specification: OSC-005 OSC Send

**Feature Branch**: `feature/osc-005` (spec directory `277-osc-005-osc-send`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement roadmap row OSC-005 (OSC send) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Transmit optional scene, beat and status messages to configured LAN peer."
Acceptance, verbatim: "Loopback fixture receives expected payload and disable stops traffic." P2, effort M,
depends on OSC-002 (integrated)."

Identifiers carry the roadmap ID: requirements `OSC-005-R1…`, success criteria `OSC-005-S1…`, research
decisions `OSC-005-D1…`, tasks `OSC-005-T01…`. FR-068 as amended on 2026-11-12 (ADR-0008, networking for
OSC) and every OSC-001, OSC-002, OSC-003, OSC-007, OSC-008 and OSC-009 requirement stay in force. This row
is the first outbound traffic the app makes; ADR-0088 records the policy change (a reviewed sender in the
OSC transport folder and in Release builds).

## Baseline: what exists today (audit of 2026-11-14, commit `8936ea3c`)

| Area | Today | Gap |
|---|---|---|
| Encoder (OSC-001 C1, OSC-002 P2) | `OSCEncoder.encode(OSCMessage)`: 4-byte padded strings, big-endian `i`/`f`/`h`/`d`, blobs, bundles; round-trips through `OSCDecoder` | none: reused as is |
| Outbound UDP | only the DEBUG `OSCLoopbackSender` (fixed to 127.0.0.1, compiled out of Release, OSC-001-R19) | **gap**: no reviewed sender |
| Local-address rule (OSC-001-R4) | `OSCPeerAddress.isLocal` (loopback, 10/8, 172.16/12, 192.168/16, 169.254/16, ::1, fe80::/10, fc00::/7); `OSCPeerAddress(text:)` parses literal IPv4/IPv6 | none: reused for the destination |
| Network switch (OSC-007) | `settings.osc.enabled` (the OSC receiver toggle, off by default) plus the visualizer badge's Stop | **gap**: nothing outbound follows it yet |
| Peer allow list (OSC-008) | "Only approved devices" and up to 16 approved local hosts (`OSCPeersCoordinator`) | **gap**: no rule for a destination |
| Rate limits (OSC-009) | inbound token buckets on an injected `OSCMonotonicClock` | **gap**: no outbound cap |
| Scene changes (SHOW-001) | `AppCoordinator.applyShowScene(_:)` applies a cue's `SceneDocument` (it has a `name`) | **gap**: no outbound hook |
| Beats (SHOW-011, MIDI-010) | `TempoCoordinator.snapshot` (`TempoSnapshot`: BPM, period, beat anchor; MIDI clock outranks manual and analysis) | **gap**: nothing turns the grid into once-per-beat events |
| Source start/stop | `AppCoordinator.start(_:)` and `stop()` | **gap**: no outbound hook |
| Compliance | `check_compliance.py` allows the Network framework in the whole `OSCTransport/` folder; `check_network_symbols.py` allows outbound `NWConnection` APIs only next to the DEBUG loopback sender, and `--release` rejects that sender | **gap**: the scan must accept the reviewed sender in Release |
| Permission | `NSLocalNetworkUsageDescription` in `project.yml`; `PermissionCatalog` `.localNetwork` | wording must cover sending |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where does the user configure sending? → A: Settings › OSC › "Send OSC" (a new screen behind one row in the existing OSC section): a "Send OSC" switch (off by default and on a fresh install), a destination address field, a destination port field, three message switches (Scene changes, Beats, Status) and "Include scene names" (OSC-005-R1, R2).
- Q: Which destinations are accepted? → A: A literal IPv4 or IPv6 address only (no host names: resolving a name is a DNS lookup, which the constitution's no-network rule and `check_network_symbols` forbid), and only in OSC-001's local ranges: loopback, 10/8, 172.16/12, 192.168/16, 169.254/16, ::1 and fc00::/7. Public, carrier-grade NAT (100.64/10), multicast, broadcast, unspecified (0.0.0.0, ::) addresses and IPv6 link-local (fe80::/10, which needs an interface zone the field does not take) are refused with a message, and the stored destination stays as it was (OSC-005-R3).
- Q: Which port range? → A: 1024-65535 (OSC-001's port rule), default 9000; refused entries keep the stored port (OSC-005-R3).
- Q: When does traffic flow? → A: Only while all hold: Send OSC on, the OSC receiver switch (OSC-007's network access switch) on, the app active in the foreground, a valid destination, and, when OSC-008's "Only approved devices" is on, the destination is an approved device. If any stops holding, sending stops at once (OSC-005-R4, R5).
- Q: What does "disable stops traffic" mean exactly? → A: Turning Send OSC off (or the network switch off, or the app leaving the foreground) cancels the connection and drops anything not yet handed to the system; no message is created or sent afterwards. Turning it back on opens a new connection (OSC-005-R5).
- Q: Which messages, and what address namespace? → A: The documented outbound namespace `/projectm/`: `/projectm/scene` when a show cue applies a scene; `/projectm/beat ,i <n>` once per beat of the current tempo (n counts beats from 1 since sending started, wrapping at 2^31−1); `/projectm/status ,s "started"` when an audio source starts and `,s "stopped"` when it stops. Scene changes and status are on by default, beats off (beats are the busiest kind) (OSC-005-R6).
- Q: Is the scene's name sent? → A: Only when "Include scene names" is on (off by default): then `/projectm/scene ,s "<name>"` with the name cut to 64 UTF-8 bytes at a character boundary; otherwise `/projectm/scene` with no arguments. Names are the user's own words, so they leave the device only on that explicit choice (OSC-005-R7).
- Q: What else is sent? → A: Nothing: no device name, no source type, no peer list, no preset or track names, no identifiers, no time stamps (OSC-005-R7).
- Q: How often may beats be sent? → A: At most once per beat; at most 4 beats a second (a tempo above 240 BPM sends every other beat as needed); no beat without a tempo with phase (OSC-005-R8).
- Q: Total rate cap? → A: At most 60 messages in any 1-second window on an injected monotonic clock; messages over the cap are dropped (never queued) and counted (OSC-005-R9).
- Q: What does the user see? → A: A status line: "Off", "Turn on the OSC receiver to send.", "Enter a destination address.", "Paused while projectM is in the background.", "The destination is not an approved device.", "Sending to <address>:<port>", or "Local Network access is off for projectM." when the system refuses; and a sent / dropped count (OSC-005-R10).
- Q: Permission? → A: The existing Local Network permission covers sending to a local address; its usage string is widened to mention sending (no new permission) (OSC-005-R11).
- Q: Is the destination backed up? → A: No. The five send keys are this device's network setup, excluded from the FILE-005 backup like OSC-008's approved peers and removed by the FILE-011 Settings erase (OSC-005-R12).

### Session 2026-11-14 (speckit-clarify)

- Q: Should beats be quantized to bars (downbeats only)? → A: No. The row says beats; a receiver can count bars from the beat number. Keeps one rule.
- Q: Does sending follow the PERF-010 recovery that turns OSC off after an abnormal exit? → A: Yes, automatically: recovery turns `settings.osc.enabled` off, which stops sending (OSC-005-R4). Send OSC itself keeps its stored value.
- Q: Does the visualizer badge change? → A: No. Sending only runs while the receiver switch is on, so the existing OSC badge with Stop is already shown; its Stop turns the switch off, which also stops sending.
- Q: Should a send failure retry? → A: No automatic retry beyond what the system does for an open UDP flow. A failed or refused connection shows the status; toggling Send OSC tries again (as OSC-001-R3 for the listener).
- Q: Are the sent and dropped counts stored, and is each message announced? → A: Counts are memory only, since launch, and never stored or exported; messages are never announced to VoiceOver (traffic is not an event), the status line is an ordinary accessible label and a refused address is shown under its field.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Tell a lighting desk about scene changes and beats (Priority: P2)

A performer runs a lighting console on a laptop at 192.168.1.40 listening on port 9001. They turn on the OSC
receiver, open Settings › OSC › Send OSC, enter 192.168.1.40 and 9001, turn on Send OSC and Beats. When a show
cue changes the scene, the console receives `/projectm/scene`; with a tempo set it receives `/projectm/beat`
on each beat.

**Why this priority**: it is the roadmap row (P2).

**Independent Test**: a real UDP listener on 127.0.0.1 receives exactly the expected bytes for a scene change and a beat.

**Acceptance Scenarios**:

1. **Given** Send OSC on to 127.0.0.1:<port> with scene names included, **When** a scene named "Intro" is applied, **Then** the listener receives exactly the bytes of `/projectm/scene ,s "Intro"`.
2. **Given** Beats on and a 120 BPM tempo, **When** the clock passes a beat, **Then** the listener receives exactly `/projectm/beat ,i 1`, and nothing more until the next beat.
3. **Given** an audio source starts and stops, **Then** `/projectm/status ,s "started"` and `,s "stopped"` arrive.

### User Story 2 - Disable stops traffic (Priority: P2)

**Acceptance Scenarios**:

1. **Given** sending to a loopback listener, **When** Send OSC is turned off and events keep coming, **Then** the listener receives nothing more over a short window.
2. **Given** sending, **When** the OSC receiver switch is turned off (Settings or the badge's Stop), **Then** nothing more is sent.
3. **Given** sending, **When** the app leaves the foreground, **Then** nothing is sent until it returns.

### User Story 3 - Only the local network (Priority: P2)

**Acceptance Scenarios**:

1. **Given** the destination field, **When** the user enters 8.8.8.8, 100.64.0.1, 224.0.0.1, 255.255.255.255, 0.0.0.0, 2001:db8::1, fe80::1 or `mixer.local`, **Then** it is refused with a message and nothing is stored.
2. **Given** "Only approved devices" on and the destination not approved, **Then** nothing is sent and the status says so.

### Edge Cases

- A burst of events over 60 in one second: the rest are dropped and counted.
- A scene name longer than 64 bytes: cut at a character boundary.
- No tempo or a tempo without phase: no beat messages.
- Destination unset: Send OSC can be on but sends nothing; the status asks for an address.
- Local Network permission denied: the status says so; nothing is retried automatically.

## Requirements *(mandatory)*

- **OSC-005-R1**: Settings › OSC MUST offer a Send OSC screen with a Send OSC switch, destination address and port, three message switches and Include scene names.
- **OSC-005-R2**: Send OSC MUST be off by default and on a fresh install, so no outbound traffic exists until the user enables it.
- **OSC-005-R3**: The destination MUST be a literal IPv4/IPv6 address in loopback, private IPv4, IPv4 link-local, ::1 or fc00::/7, and the port 1024-65535; anything else (host names, public, CGNAT, multicast, broadcast, unspecified, IPv6 link-local) MUST be refused with a message, keeping the stored value.
- **OSC-005-R4**: Messages MUST be sent only while Send OSC is on, the OSC network switch (OSC-007) is on, the app is active in the foreground, the destination is valid and, with OSC-008's allow list on, approved.
- **OSC-005-R5**: When any condition of R4 stops holding, the connection MUST be cancelled and unsent messages dropped at once; no message MUST be sent afterwards until the conditions hold again.
- **OSC-005-R6**: Messages MUST be OSC 1.0 messages in the `/projectm/` namespace: `/projectm/scene`, `/projectm/beat ,i n`, `/projectm/status ,s started|stopped`, each kind sent only when its switch is on (defaults: scene on, beat off, status on).
- **OSC-005-R7**: Scene names MUST be sent only with Include scene names on (cut to 64 UTF-8 bytes); no other user or device data MUST be sent.
- **OSC-005-R8**: Beats MUST be sent at most once per beat of the current tempo grid and at most 4 per second, and never without a tempo with phase.
- **OSC-005-R9**: At most 60 messages MUST be sent in any 1-second window (injected clock); excess messages are dropped and counted, never queued.
- **OSC-005-R10**: The Send OSC screen MUST show a status line and the sent and dropped counts.
- **OSC-005-R11**: Sending MUST use the existing Local Network permission; its usage string MUST mention sending.
- **OSC-005-R12**: The send settings MUST stay on this device: excluded from backup, removed by the Settings erase, reset by the UI-test reset.
- **OSC-005-R13**: The encoder MUST produce bytes that the OSC-002 parser decodes back to the same message.

### Key Entities

- **Send destination**: a validated local address and port (stored on this device only).
- **Send options**: Send OSC, the three message kinds, Include scene names.
- **Outbound event**: scene (optional name), beat number, status word; memory only.
- **Send cap**: the last 60 send times (memory only).

## Success Criteria *(mandatory)*

- **OSC-005-S1**: The loopback fixture receives byte-exact scene and beat payloads (100% of runs).
- **OSC-005-S2**: After disable (Send OSC off, network switch off, background), the fixture receives zero datagrams over a 300 ms window.
- **OSC-005-S3**: Every non-local destination in the test list is refused (100%).
- **OSC-005-S4**: No more than 60 messages leave in any 1 s window under a flood of events.
- **OSC-005-S5**: A user configures sending to a LAN peer in one screen, with at most 4 entries (address, port, switch, one kind).

## Assumptions

- One destination at a time; multiple destinations or discovery (OSC-011) are out of scope.
- Bundles and time tags are not sent (OSC-006 handles bundles on the receive side).
- The device check with a real LAN receiver is a `{device}` task.
