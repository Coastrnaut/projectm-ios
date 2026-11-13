# Feature Specification: OSC-001 OSC Receiver

**Feature Branch**: `feature/osc-001` (spec directory `032-osc-001-osc-receiver`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement roadmap row OSC-001 (OSC receiver) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Listen on user-selected local
UDP port when enabled." Acceptance, verbatim: "Valid OSC float packet updates test value and
disable closes listener." Depends on MOD-001 (typed parameter registry, integrated). Owner ruling
(ADR-0008, FR-068 amendment): the Network framework only in the one OSC transport folder, off by
default, local network only, a local-network usage description, and a privacy policy update."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `OSC-001-R1…`, success criteria `OSC-001-S1…`, tasks `OSC-001-T01…`. FR-068 as
amended on 2026-11-12 (`specs/001-ios-projectm-visualizer/spec.md`) and the MOD-001 requirements
(`specs/028-mod-001-typed-parameter-registry/spec.md`) stay in force.

## Baseline: what exists today (audit of 2026-11-13, commit `ba60b9d`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Network code | None. FR-068 forbids networking; the 2026-11-12 amendment allows the Network framework only under `Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport/`, a folder that does not exist yet. `scripts/check_compliance.py` enforces the boundary. | No listener, no transport. |
| OSC | No OSC code anywhere in `Packages/` or `Apps/`. | No decoder for OSC messages. |
| Parameters | MOD-001's `ParameterStore` holds typed values with clamping; `ModulationPolicy.allowsExternalControl` says whether MIDI or OSC may set a value. No external control source writes to a store yet. | Nothing applies an external value under that policy. |
| Settings | Visual, glow, Reduce flashing, performance overlay, Licenses. | No OSC setting. |
| Privacy | The policy and App Privacy answers say the app makes no network connections of its own. Info.plist has no local-network usage description. | Both must describe the listener before it ships. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What is the "test value" the acceptance criterion updates? → A: One registered parameter, `osc.receiver.testValue` (continuous 0…1, default 0, unit none, policy external control allowed, not modulatable), in a small registry the OSC receiver owns, reached at one fixed OSC address, `/projectm/test`. Settings shows its current value under the OSC toggle ("Test value 0.42"), so a user can check that their controller reaches the app before OSC-003 adds real routes. It feeds nothing visual, so OSC-001 cannot change what the user sees on the visualization (OSC-001-R6, R7).
- Q: Which OSC messages does OSC-001 decode, and how does that leave room for OSC-002? → A: A single OSC message (no bundles) whose address starts with `/`, whose type tag string starts with `,`, and whose arguments are 32-bit floats (`f`) or 32-bit integers (`i`), at most 16 arguments, in a datagram of at most 1,472 bytes (an Ethernet-sized UDP payload; larger datagrams are rejected before decoding). Every read is bounds-checked and 4-byte aligned; anything else (strings, blobs, bundles, other tags, bad padding, trailing bytes) is rejected with a typed reason and never crashes. The decoder is one pure value type with a typed error enum and an argument enum, so OSC-002 adds `s`/`b`/bundle cases and its fuzz corpus without changing callers (OSC-001-R8 to R11).
- Q: Which addresses and values change the test value? → A: Only `/projectm/test` with exactly one numeric argument. A float or an integer is converted to a number and handed to the parameter store, which clamps it to 0…1; NaN and infinity are refused by the store and change nothing. Any other address, argument count or type is ignored (counted, not applied). Allowlisted routes to other parameters are OSC-003; learn is OSC-004 (OSC-001-R12, R13).
- Q: Who may send, and how is "local network only" enforced? → A: The listener never connects out and never resolves a host. It refuses the cellular interface, and it accepts datagrams only from loopback, private IPv4 (10/8, 172.16/12, 192.168/16), IPv4 link-local (169.254/16), IPv6 loopback, link-local (fe80::/10) and unique-local (fc00::/7) addresses; any other source is dropped without reading its data. At most 8 peers are tracked at once (the oldest is dropped for a ninth). A user-approved peer allowlist is OSC-008 and a per-source rate limit is OSC-009 (OSC-001-R4, R5, R14).
- Q: Which port, and what is remembered? → A: The user types a port; 1024-65535 is accepted, the default is 9000 (common for OSC controllers), and anything else is refused with a message and keeps the previous port. The toggle (absent → off) and the port (absent or invalid → 9000) are stored as two user settings. A fresh install opens no listener. When the user has turned OSC on, the listener runs only while the app is active in the foreground: it closes when the app leaves the foreground and reopens on return, so it never listens in the background (OSC-001-R1 to R3, R15).
- Q: What status does OSC-001 show, given that OSC-007 owns the network access switch? → A: The Settings footer under the toggle says "Off", "Starting…", "Listening on port 9000", or why it failed ("Port 9000 is in use. Choose another port." / "Local network access is off for projectM in Settings › Privacy & Security › Local Network."). OSC-007 adds the visible listener status outside Settings, the stop control and the fresh-install socket audit (OSC-001-R16).
- Q: How is "disable closes listener" proved? → A: Turning the toggle off (or the app leaving the foreground) cancels the listener and every peer connection and reports "Off" only after the system confirms the listener is cancelled. A host integration test sends a float over loopback, sees the test value change, disables, then shows that a second packet changes nothing and that the same port can be bound again (OSC-001-R3, S2).
- Q: What does the privacy policy and App Store answer change? → A: The policy gains an "OSC control on your local network" section: off by default, listens only on the local network while turned on and the app is in the foreground, never connects out, sends nothing, stores nothing it receives except the current test value in memory, and iOS asks for Local Network permission. The App Privacy answer stays "Data Not Collected" (nothing leaves the device; received values are not stored or sent), which the owner confirms in App Store Connect; `docs/release/app-privacy.md` records the reasoning (OSC-001-R17, R18).
- Q: Where does the code live? → A: The decoder, the address scope check, the dispatcher and the receiver's state machine are pure Swift in the `PerformanceControl` target (Linux-testable). Only the transport, the code that touches the Network framework, lives in `Sources/PerformanceControl/OSCTransport/` and compiles only where the Network framework exists. A test-only loopback sender for the integration test lives in the same folder and compiles only in debug builds, so the shipping app contains no sending code and the test targets stay free of networking APIs (OSC-001-R19).
- Q: When does a typed port take effect? → A: When the user submits the field (Return/Done) or leaves it, never per keystroke, so a half-typed "90" never opens port 90. A refused entry shows "Use a port from 1024 to 65535." under the field and the field returns to the stored port (OSC-001-R2).
- Q: After a failure (port in use, permission denied, network lost), does the receiver retry by itself? → A: No automatic retry loop. The toggle stays on and the status shows the failure; the receiver tries again only when the user toggles it, changes the port, or the app returns to the foreground. This keeps the socket lifecycle tied to explicit user or app events (OSC-001-R3, R16).
- Q: What does the receiver record about traffic? → A: In-memory counters only (datagrams received, applied, rejected by reason, dropped as non-local), readable by tests and later by OSC-007's status; never logged with payloads, never stored, never shown with peer addresses in this row (OSC-001-R13, R15).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Turn OSC on and control the test value (Priority: P1)

A performer with an OSC controller app on a laptop or tablet on the same Wi-Fi opens Settings,
turns on "OSC receiver", keeps port 9000, and sends `/projectm/test 0.42`. The test value under the
toggle reads 0.42.

**Why this priority**: It is the row's observable behavior and the first half of its acceptance.

**Independent Test**: Start the receiver on a free port, send one float message over loopback, read
the test value.

**Acceptance Scenarios**:

1. **Given** OSC is off, **When** the user turns it on with port 9000, **Then** the status reads
   "Listening on port 9000" once the system has opened the port.
2. **Given** the receiver is listening, **When** a local peer sends `/projectm/test` with float
   0.42, **Then** the test value becomes 0.42.
3. **Given** the receiver is listening, **When** a peer sends integer 1 to `/projectm/test`,
   **Then** the test value becomes 1; a float of 7 is clamped to 1 and −3 to 0.
4. **Given** the receiver is listening, **When** a message for any other address arrives, **Then**
   the test value does not change.

---

### User Story 2 - Turn OSC off (Priority: P1)

The performer turns the toggle off. The port closes; packets sent afterwards do nothing.

**Why this priority**: The second half of the acceptance and the core privacy promise.

**Independent Test**: After the loopback test above, disable, send again, see no change, and bind
the same port again.

**Acceptance Scenarios**:

1. **Given** the receiver is listening, **When** the user turns the toggle off, **Then** the
   listener and every peer connection are cancelled and the status reads "Off".
2. **Given** OSC was just turned off, **When** a peer sends to the old port, **Then** nothing
   changes.
3. **Given** OSC is on, **When** the app leaves the foreground, **Then** the listener closes, and it
   reopens on the same port when the app returns.

---

### User Story 3 - Choose a port (Priority: P2)

The performer's controller sends to port 8000, so they type 8000.

**Independent Test**: Port validation unit tests; a port change while listening moves the listener.

**Acceptance Scenarios**:

1. **Given** OSC is on at 9000, **When** the user enters 8000, **Then** the listener closes on 9000
   and opens on 8000.
2. **Given** any state, **When** the user enters 80, 70000, an empty field or letters, **Then** the
   entry is refused with "Use a port from 1024 to 65535." and the previous port stays.
3. **Given** another app holds the port, **When** OSC starts, **Then** the status explains that the
   port is in use and suggests choosing another; nothing crashes and the toggle stays on.

---

### User Story 4 - Hostile or broken packets (Priority: P1)

Anything on the local network can send datagrams to an open port. Malformed, oversized, unsupported
or non-local packets must be dropped without crashing, without unbounded memory and without
changing the test value.

**Independent Test**: Decoder unit tests for each rejection reason, plus a fixed-seed fuzz run of
random and mutated packets.

**Acceptance Scenarios**:

1. **Given** a packet that is truncated, unpadded, has no `,` type tag, an unterminated string, an
   unsupported tag, extra bytes or more than 16 arguments, **When** it is decoded, **Then** it is
   rejected with a reason and nothing is applied.
2. **Given** a datagram larger than 1,472 bytes, **When** it arrives, **Then** it is rejected before
   decoding.
3. **Given** a datagram from a public internet address, **When** it arrives, **Then** it is dropped.
4. **Given** thousands of random and mutated packets, **When** they are decoded, **Then** none
   crashes, none is accepted unless well formed, and the run takes under a second.

---

### User Story 5 - Accessible settings (Priority: P2)

A VoiceOver user finds the "OSC receiver" toggle, the port field and the status, and hears the test
value.

**Acceptance Scenarios**:

1. **Given** Settings, **When** VoiceOver focuses the toggle, the port field and the status,
   **Then** each has a label and value ("OSC receiver, off"; "Port, 9000"; "Listening on port
   9000"; "Test value, 0.42").

### Edge Cases

- The user toggles on and off rapidly: every start is matched by a cancel; at most one listener
  exists at a time, and a late "ready" from a cancelled listener does not change the status.
- Local Network permission denied: the status says how to allow it; turning the toggle off and on
  after allowing it retries.
- The Wi-Fi network changes while listening: the listener keeps its port; if the system fails it,
  the status shows the failure and the user can toggle it.
- A flood of valid packets: each is applied off the main thread and off the audio thread; the test
  value shows the latest. Bounding the rate is OSC-009.
- A packet for `/projectm/test` with two arguments, a string or a blob: ignored.
- NaN or infinity: refused by the parameter store; the value is unchanged.
- The store refuses external control (a parameter with `allowsExternalControl` false): never
  changed by OSC.
- Port 9000 on a fresh install with OSC off: no socket is opened.

## Requirements *(mandatory)*

### Functional Requirements

- **OSC-001-R1**: OSC control MUST be off on a fresh install and MUST open no network listener
  until the user turns it on.
- **OSC-001-R2**: While on, and while the app is active in the foreground, the app MUST listen for
  UDP datagrams on the user's port, 1024-65535 (default 9000); entries outside that range or not a
  number MUST be refused with a message, keeping the previous port. A port entry MUST take
  effect only when submitted or when the field loses focus.
- **OSC-001-R3**: Turning OSC off, changing the port, or the app leaving the foreground MUST cancel
  the listener and every peer connection; the off state MUST be reported only after the listener is
  cancelled; afterwards no datagram MUST change any value. A failed listener MUST NOT retry by
  itself; it retries only on a toggle, a port change or the return to the foreground.
- **OSC-001-R4**: The listener MUST use only the local network: it MUST never connect out or
  resolve a host, MUST refuse the cellular interface, and MUST drop datagrams from any address that
  is not loopback, private IPv4, IPv4 link-local, IPv6 link-local or IPv6 unique-local.
- **OSC-001-R5**: At most 8 peers MUST be tracked at once; a new peer beyond that MUST cause the
  least recently started peer to be cancelled.
- **OSC-001-R6**: The receiver MUST own one test parameter, `osc.receiver.testValue` (continuous
  0…1, default 0, external control allowed), reached at the OSC address `/projectm/test`.
- **OSC-001-R7**: No OSC value MUST reach projectM or any visual in this row (Constitution VIII,
  ADR-0008 decision 5).
- **OSC-001-R8**: The decoder MUST accept one OSC message per datagram: a null-terminated address
  starting with `/` padded to 4 bytes, a null-terminated type tag string starting with `,` padded to
  4 bytes, then big-endian 32-bit `f` and `i` arguments, with no bytes left over.
- **OSC-001-R9**: The decoder MUST bound every read and reject, with a typed reason and without
  crashing: datagrams over 1,472 bytes, empty or unpadded data, a missing terminator, an address
  over 255 bytes or not starting with `/` or containing bytes outside printable ASCII, a missing
  `,`, more than 16 arguments, an unsupported tag, truncated arguments, trailing bytes, and bundles
  (`#bundle`, reported as unsupported until OSC-002).
- **OSC-001-R10**: The decoder MUST allocate at most in proportion to the bounded datagram (no
  allocation sized by a field read from the packet).
- **OSC-001-R11**: The decoder's message, argument and error types MUST be extensible by OSC-002
  (strings, blobs, bundles) without changing existing callers.
- **OSC-001-R12**: A message for `/projectm/test` with exactly one `f` or `i` argument MUST set the
  test parameter through the parameter store (clamped to its range); a non-finite float MUST change
  nothing.
- **OSC-001-R13**: The dispatcher MUST apply a value only to a registered parameter whose policy
  allows external control; every other message MUST be ignored and counted by reason. Counters
  MUST stay in memory and MUST NOT record payloads or peer addresses.
- **OSC-001-R14**: Packets MUST be decoded and applied on a dedicated serial queue, never on the
  main thread or an audio thread.
- **OSC-001-R15**: The toggle and the port MUST be stored as user settings (`settings.osc.enabled`,
  absent → off; `settings.osc.port`, absent or invalid → 9000) and nothing received MUST be stored.
- **OSC-001-R16**: Settings MUST show an "OSC receiver" toggle, a port field, a status line (Off,
  Starting…, Listening on port N, or the failure with what to do) and the test value, each with an
  accessibility label and value.
- **OSC-001-R17**: The app's Info.plist MUST carry a local-network usage description that says what
  the permission is for, and no Bonjour service (OSC-011 adds discovery).
- **OSC-001-R18**: The privacy policy MUST describe the listener (off by default, local network
  only, foreground only, nothing sent or stored) before the feature ships; the App Privacy
  reasoning MUST be recorded for the owner.
- **OSC-001-R19**: Network framework code MUST live only in
  `Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport/` and MUST compile out where
  the framework is unavailable (Linux); no other networking API MUST be used anywhere; code that
  sends datagrams MUST exist only in debug builds, for tests.

### Key Entities

- **OSC message**: an address and an ordered list of arguments (float or integer in this row).
- **Decode error**: why a datagram was rejected (oversized, truncated, bad padding, bad address,
  missing type tags, unsupported tag, too many arguments, trailing bytes, bundle unsupported).
- **OSC route**: an address bound to a parameter ID (one fixed route in this row; OSC-003 makes
  them configurable).
- **Receiver state**: off, starting(port), listening(port), failed(port, reason).
- **Receiver counters**: datagrams received, applied, rejected by reason, dropped as non-local.
- **OSC settings**: enabled flag and port.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **OSC-001-S1**: A valid `/projectm/test` float datagram sent over loopback to an enabled receiver
  changes the test value to that float in 100% of integration test runs on the macOS host.
- **OSC-001-S2**: After disable, a second datagram changes nothing and the same port can be opened
  again, in 100% of integration test runs.
- **OSC-001-S3**: Every malformed case in the decoder tests is rejected with its expected reason,
  and a fixed-seed fuzz of at least 20,000 random and mutated packets causes no crash, accepts only
  well-formed packets and finishes in under 1 s.
- **OSC-001-S4**: A fresh install opens no listener (the toggle reads off and the receiver state is
  off), shown by a unit test of the default settings and a UI test.
- **OSC-001-S5**: The compliance check passes with Network framework code only in the one allowed
  folder; the shipping (Release) build contains no datagram-sending symbol.
- **OSC-001-S6**: Each unit test runs in about a second or less, the package suite in under a
  minute, the UI test in under 30 s (owner rule 7).
- **OSC-001-S7** `{device}`: On a physical device on a Wi-Fi network, a controller on another
  computer changes the test value, and turning OSC off stops it (last stage, owner).

## Hand-off to OSC-002 to OSC-012

- OSC-002 extends the decoder (strings, blobs, bundles, a larger fuzz corpus) behind the same
  `OSCMessage`/`OSCArgument`/`OSCDecodeError` types.
- OSC-003 replaces the single fixed route with an allowlisted route table to registry IDs; the
  dispatcher's policy check stays.
- OSC-007 adds the visible listener status outside Settings, a stop control and the fresh-install
  socket audit; it reads the receiver state this row publishes.
- OSC-008 adds a user peer allowlist on top of the local-address scope; OSC-009 adds per-source and
  per-target rate limits in front of the dispatcher.
- OSC-005 (send) needs its own release-build sender in the same folder; the debug-only loopback
  sender here is not it.

## Assumptions

- UDP only; OSC over TCP (SLIP framing) is out of scope.
- One listener for the whole app; the IPv4 and IPv6 local addresses the system binds are both
  accepted.
- Simulator and host runs prove the loopback path only; Wi-Fi from another device is the device task.
- The App Store Connect privacy answer is changed (or confirmed unchanged) by the owner.
