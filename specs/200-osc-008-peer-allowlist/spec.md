# Feature Specification: OSC-008 OSC Peer Allowlist

**Feature Branch**: `feature/osc-008` (spec directory `200-osc-008-peer-allowlist`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement roadmap row OSC-008 (OSC peer allowlist) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Optionally restrict packets to
user-approved local peers." Acceptance, verbatim: "Unapproved source address cannot change a scene."
P1, depends on OSC-001 (integrated)."

Identifiers carry the roadmap ID: requirements `OSC-008-R1…`, success criteria `OSC-008-S1…`, research
decisions `OSC-008-D1…`, tasks `OSC-008-T01…`. FR-068 as amended on 2026-11-12 (ADR-0008, networking
for OSC) and every OSC-001, OSC-002, OSC-003, OSC-007 and OSC-009 requirement stay in force except where
this spec narrows them (OSC-001-R13, R15 on peer addresses; see ADR-0058). Network access is not
widened: the listener, its local-only scope and its lifecycle are unchanged; the only new use of the
network API is reading the sender's address the transport already receives.

## Baseline: what exists today (audit of 2026-11-14, commit `f089007a`)

| Part of the row | Today | Gap |
|---|---|---|
| Local-only scope | OSC-001-R4: `OSCPeerAddress.isLocal` (loopback, private and link-local IPv4, IPv6 loopback, link-local, unique-local; IPv4-mapped judged as IPv4) checked per peer connection in `NetworkDatagramTransport.accept`; others dropped and counted (`droppedNonLocal`) | none |
| Source of a datagram | `OSCTransportEvent.datagram(bytes, source:)` carries only an opaque `OSCSourceID` per peer connection (OSC-009-R3); the address is discarded after the local check | **gap**: the receiver cannot tell which host sent a datagram |
| Dispatch | `OSCReceiver.handle` → `OSCDispatcher.handle` (rate limit → decode → OSC-003 routes → store, live values) | **gap**: no per-host filter |
| Settings | OSC section: toggle, port, status, test value, rate-limited count, OSC Routes link | **gap**: no approved-devices list |
| Privacy | OSC-001-R13/R15: counters only, peer addresses never stored or shown | the allowlist must store the hosts the user approves (ADR-0058) |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Is the allowlist on by default? → A: No. "Only approved devices" is off by default, so OSC behaves exactly as before (every local peer may send). The switch is stored under `settings.osc.peerAllowlist.enabled` (Bool, absent → off) (OSC-008-R1).
- Q: What identifies a peer? → A: Its host address only (IPv4 4 bytes or IPv6 16 bytes); the source port is ignored, because controllers send from changing ephemeral ports. An IPv4-mapped IPv6 address (`::ffff:a.b.c.d`) is the same peer as `a.b.c.d`. An IPv6 zone/interface index is ignored. Host names are never resolved (OSC-008-R2).
- Q: Which addresses may be approved? → A: Only addresses that pass OSC-001's local rule (`isLocal`): loopback, private and link-local IPv4, IPv6 loopback, link-local and unique-local. A stored entry that is not local or does not parse is dropped on load (OSC-008-R3).
- Q: How are peers approved? → A: From the "Recently blocked" list: while the allowlist is on, the last 4 distinct hosts whose datagrams were dropped are kept in memory (most recent first) with an "Allow" button. Typing an address is not offered: it avoids typos and keeps every entry a host that really sent to this device. Approved entries can be removed one by one (OSC-008-R4, R5).
- Q: How many approved peers? → A: At most 16. When the list is full, "Allow" is disabled with a note to remove one first (no silent eviction of a host the user approved) (OSC-008-R5).
- Q: What happens to a datagram from an unapproved host? → A: While the allowlist is on it is dropped before rate limiting, decoding and dispatch: nothing is decoded, no route, parameter, live value or limiter bucket changes. It is counted (`droppedUnapproved`) and its host is noted in the recently blocked list. A datagram whose host the transport cannot tell is treated as unapproved (fail closed) (OSC-008-R6, R7).
- Q: Why before the rate limiter? → A: So an unapproved host cannot use up the global budget and starve approved controllers (OSC-008-R6).
- Q: When does a change take effect? → A: From the next datagram: the check runs per datagram against the current list, so turning the allowlist on, approving or removing a host needs no listener restart and affects peers already connected (OSC-008-R8).
- Q: What does the user see? → A: In Settings › OSC an "Approved Devices" row (value "Off" or "N approved") opens a screen with the "Only approved devices" toggle, the approved list (address, Remove), "Recently blocked" (address, Allow) and a "Blocked" count since OSC was last turned on. With the switch on and no approved device, the screen says every message is blocked (OSC-008-R9).
- Q: Where are approved hosts stored, and do they travel? → A: `settings.osc.approvedPeers`, an array of canonical address strings (dotted IPv4; IPv6 as 8 lowercase hex groups), on this device only: both new keys are excluded from the FILE-005 backup (network addresses are specific to this device's network, like `settings.osc.enabled`) and are removed by the FILE-011 Settings erase and the UI-test reset. The recently blocked list and the counter are memory only and are cleared when OSC is turned off (OSC-008-R10, R11).
- Q: Does this override a default? → A: It narrows OSC-001-R13/R15 ("never store or show peer addresses"): hosts the user approves are stored, and recently blocked local hosts are shown in memory. ADR-0058 records this; the privacy policy says so (OSC-008-R12).
- Q: Is a blocked datagram announced (VoiceOver or a status cue)? → A: No. A blocked host could send hundreds per second; only the count and the recently blocked list change, read on OSC-009's gated refresh (at most ~30 refreshes a second), so no main-thread work is added per datagram (OSC-008-R7, S4).
- Q: Can the list be edited while OSC is off? → A: Yes. The Approved Devices screen is reachable whether or not OSC is on, so a user can prepare or prune the list; "Recently blocked" is empty while OSC is off (OSC-008-R9, R11).
- Q: Does the rest of OSC change? → A: No. Non-local peers are still dropped by the transport first (OSC-001-R4), and approved datagrams go through OSC-009 limits and OSC-003 routes unchanged.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Only my controller can change the show (Priority: P1)

A performer on shared Wi-Fi turns on "Only approved devices" and approves their tablet. Another device on
the same network sends `/projectm/param/glow.intensity 1.0`; the glow does not change. The tablet's
message does change it.

**Why this priority**: it is the roadmap row's acceptance ("Unapproved source address cannot change a scene").

**Independent Test**: a receiver with a fake transport and the allowlist on: a routed message from
an unapproved host leaves every parameter value and live value unchanged; the same message from an
approved host applies.

**Acceptance Scenarios**:

1. **Given** the allowlist on with 192.168.1.20 approved, **When** a routed glow message arrives from 192.168.1.30, **Then** no parameter, live value or limiter state changes and `droppedUnapproved` rises by one.
2. **Given** the same, **When** the message arrives from 192.168.1.20 (any port), **Then** the glow intensity changes.
3. **Given** the allowlist off (default), **When** the message arrives from any local host, **Then** it applies as before.
4. **Given** the allowlist on, **When** a datagram arrives whose host is unknown, **Then** it is dropped.

### User Story 2 - Approve the device that just tried (Priority: P2)

With the allowlist on, the user opens Settings › OSC › Approved Devices, sees their controller under
"Recently blocked" and taps Allow; its next message applies. They can remove it again.

**Acceptance Scenarios**:

1. **Given** a blocked datagram from fe80::1, **When** the user taps Allow, **Then** fe80::1 is stored as approved and its next datagram applies.
2. **Given** 16 approved hosts, **When** another host is blocked, **Then** Allow is unavailable with a note.
3. **Given** an approved host, **When** the user removes it, **Then** its next datagram is dropped.

### Edge Cases

- A stored entry that is malformed or not local (edited defaults, restored older data): dropped on load.
- 127.0.0.1 and `::ffff:127.0.0.1` are the same peer.
- A malformed datagram from an unapproved host: dropped without decoding (no `rejected` count).
- A malformed datagram from an approved host: rejected by the decoder as before.
- Turning OSC off clears the recently blocked list; the approved list stays.

## Requirements *(mandatory)*

- **OSC-008-R1**: The app MUST offer an "Only approved devices" switch, off by default (`settings.osc.peerAllowlist.enabled`, absent → off); while off, OSC behaves exactly as without this feature.
- **OSC-008-R2**: A peer MUST be identified by its host address only (IPv4 or IPv6), ignoring port and IPv6 zone; an IPv4-mapped IPv6 address MUST match its IPv4 form.
- **OSC-008-R3**: Only addresses that pass OSC-001's local rule MAY be approved or stored; non-local or unreadable stored entries MUST be dropped on load.
- **OSC-008-R4**: While the switch is on, the receiver MUST keep in memory the last 4 distinct blocked hosts, most recent first.
- **OSC-008-R5**: The user MUST be able to approve a recently blocked host and remove an approved one; the approved list MUST hold at most 16 hosts, and approving MUST be refused when it is full.
- **OSC-008-R6**: While the switch is on, a datagram whose host is not approved, or whose host is unknown, MUST be dropped before the rate limiter, the decoder and dispatch, changing no parameter, live value, limiter state or route.
- **OSC-008-R7**: Every such drop MUST be counted in memory (`droppedUnapproved`) and MUST NOT record the payload.
- **OSC-008-R8**: Changes to the switch or the list MUST apply from the next datagram, without restarting the listener.
- **OSC-008-R9**: Settings › OSC MUST show an "Approved Devices" row and screen with the switch, the approved list (Remove), "Recently blocked" (Allow), the blocked count and, when on with an empty list, a note that every message is blocked; every control has an accessibility label and identifier.
- **OSC-008-R10**: Approved hosts MUST be stored only on this device (`settings.osc.approvedPeers`); both new keys MUST be excluded from the FILE-005 backup, removed by the FILE-011 Settings erase and by the UI-test reset, and listed in the device test's allowed keys.
- **OSC-008-R11**: The recently blocked list and the blocked count MUST be memory only and cleared when OSC is turned off.
- **OSC-008-R12**: The privacy policy MUST describe the option and that approved addresses are stored only on the device.
- **OSC-008-R13**: No new network capability: the transport MUST only pass the address it already reads for the local check.

### Key Entities

- **Peer host**: the normalized host address of a sender (IPv4 or IPv6 bytes).
- **Peer allowlist**: switch, approved hosts (≤16), recently blocked hosts (≤4, memory), blocked count (memory).

## Success Criteria *(mandatory)*

- **OSC-008-S1**: With the allowlist on, 100% of datagrams from unapproved hosts (including a seeded fuzz of malformed and foreign-source packets) leave parameter values and live values unchanged, while an approved host's valid message applies.
- **OSC-008-S2**: With the allowlist off, every existing OSC test passes unchanged.
- **OSC-008-S3**: A user approves a blocked controller in at most 3 taps from Settings › OSC.
- **OSC-008-S4**: The filter adds O(1) work per datagram (a set lookup) and no main-thread work per datagram.

## Assumptions

- The device LAN check (a second device on Wi-Fi) is last and tagged `{device}`; loopback stands in on the simulator.
- Scenes as files are unaffected: OSC values are live values (OSC-003-R5), never written into a scene; "change a scene" means change what the scene shows through OSC routes or the test value.
