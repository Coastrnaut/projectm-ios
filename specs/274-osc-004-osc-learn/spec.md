# Feature Specification: OSC-004 OSC Learn

**Feature Branch**: `feature/osc-004` (spec directory `274-osc-004-osc-learn`)

**Created**: 2026-11-14

**Status**: Implemented (OSC-004-T14 {device} open)

**Input**: User description: "Implement roadmap row OSC-004 (OSC learn) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Capture an incoming OSC address and bind it
to selected control." Acceptance, verbatim: "Learn mode records one allowed address and exits after timeout."
P2, depends on OSC-003 (integrated)."

Identifiers carry the roadmap ID: requirements `OSC-004-R1…`, success criteria `OSC-004-S1…`, research
decisions `OSC-004-D1…`, tasks `OSC-004-T01…`. FR-068 as amended on 2026-11-12 (ADR-0008, networking for
OSC) and every OSC-001, OSC-002, OSC-003, OSC-007, OSC-008 and OSC-009 requirement stay in force. Network
access is not widened: learn only observes messages the existing receiver already decodes.

## Baseline: what exists today (audit of 2026-11-14, commit `dc3c3fc1`)

| Area | Today | Gap |
|---|---|---|
| Receiver (OSC-001, OSC-007) | `OSCReceiver` listens only while the user's OSC switch is on and the app is in the foreground; `OSCReceiverCoordinator.state` is `.listening(port)` then | none |
| Peer allow list (OSC-008) | `OSCReceiver.handle` drops a datagram from an unapproved host before the dispatcher (`droppedUnapproved`) | none: learn never sees such a datagram |
| Rate limits (OSC-009) | `OSCDispatcher.handle` admits a datagram per source and globally before decoding | none: learn sits after this check |
| Parser (OSC-002) | `OSCDecoder.decodePacket`: a malformed datagram is rejected whole; bundles yield messages depth-first | none |
| Routes (OSC-003) | literal route table: test route, `/projectm/param/<id>`, built-in glow aliases, ≤ 16 user aliases (`OSCRouteAliasRules`, stored as `<address>=<id>` lines under `settings.osc.aliases`); unknown addresses ignored and counted | **gap**: an alias can only be typed by hand |
| Learn pattern (MIDI-003, MIDI-005) | `MIDILearnSession<Target>`: start for a target with a deadline on an injected clock, the first eligible event of a batch binds, cancel, expire; `MIDIMappingCoordinator` adds the scheduler, status texts and `.midi` announcements | **gap**: nothing captures an OSC address |
| Announcements | `AccessibilityAnnouncer` has an `.osc` lane | none |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where is learn started? → A: On the OSC Routes screen (Settings › OSC › OSC Routes), in a "Learn an address" section with one Learn button per routable parameter (the four glow parameters, OSC-003's routable list). A selected parameter's row is the "selected control" of the roadmap row. No other entry point in this row (OSC-004-R1).
- Q: When can learn start? → A: Only while the receiver is actually listening (`.listening`, OSC-001/OSC-007). Otherwise the Learn buttons are disabled and the section says "Turn on the OSC receiver to learn an address." If the receiver stops while learning (switch off, background, failure), learn ends with "Learning stopped: the OSC receiver is off." (OSC-004-R2, R9).
- Q: Which messages may be learned? → A: A message that already passed OSC-008 (approved host, when the allow list is on), OSC-009 (rate limits) and OSC-002 (well-formed datagram), whose address passes OSC-003's alias rules (`/`, 2–64 of `A-Z a-z 0-9 / . _ -`, no `//`, no trailing `/`, so no pattern characters) and is not under `/projectm/` (the app's own namespace: the connection test and standard routes are never learned), with exactly one finite numeric argument (`f`, `i`, `h` or `d`), the argument OSC-003 routes accept. Strings, blobs, true/false/nil/impulse and multi-argument messages are ignored; learn keeps waiting (OSC-004-R3).
- Q: A message from a peer not on the allow list? → A: Ignored, never offered as "allow this peer?" and never auto-allowed: OSC-008 drops it before decoding, so learn cannot see it. Approved Devices already lists recently blocked hosts with Allow; the learn section's footer says unapproved devices are ignored (OSC-004-R4).
- Q: Several eligible messages in a burst or a bundle? → A: Only the first eligible message in arrival order (depth-first within a bundle) is recorded; capture disarms in the same locked step, so later messages of the burst are handled as ordinary traffic and never make a second binding (OSC-004-R5).
- Q: Does the learning message drive the parameter? → A: No. It only creates the route; values apply from the next message, as with MIDI-003 (OSC-004-R6).
- Q: How is the binding stored? → A: As an OSC-003 user alias (`<address>=<parameter ID>` under the existing `settings.osc.aliases`), so it shows in OSC Routes, can be turned off or swiped away, is in the FILE-005 backup and the FILE-011 erase, and reaches the dispatcher through `setRoutes` at once. If the address was turned off, learning turns it on. No new settings key (OSC-004-R7).
- Q: The address already has a route? → A: If it already reaches the selected parameter: nothing changes, "… already controls …". If it is your alias to another parameter: it is replaced (moved to the selected parameter) and the status names the previous parameter, without a dialog: learn is used with one hand on the controller, MIDI-003 replaces the same way, and the alias can be swiped away. Other addresses of the parameter stay (OSC allows several addresses per parameter). Standard and built-in routes cannot be learned (they are under `/projectm/`) (OSC-004-R7).
- Q: The alias list is full (16)? → A: Learn ends without binding: "No more aliases fit (16). Delete one first." (OSC-004-R7).
- Q: Timeout? → A: 10 seconds on an injected monotonic clock (shorter than MIDI-003's 30 s: an OSC controller is in the performer's hand on the same network, and a listener armed for learning should not wait long). Learn ends with "OSC learn timed out. Nothing was bound." Cancel ends with "OSC learn cancelled." Starting learn for another parameter restarts it for that one (newest wins); leaving the screen cancels it silently (OSC-004-R8).
- Q: Announcements? → A: Start, bound, replaced, already, full, timed out, cancelled and stopped texts go through `AccessibilityAnnouncer` on the `.osc` lane; incoming traffic is never announced (OSC-004-R10).
- Q: Privacy? → A: The learned address is the controller's message address (not a peer address) and is stored only as the alias; the sender's host is never recorded by learn; the captured value is discarded (OSC-004-R11).

### Session 2026-11-14 (speckit-clarify)

- Q: Is the captured address shown before it is bound (a confirm step)? → A: No: the acceptance is "records one address"; a confirm step would leave learn armed while the performer looks away. The bound row appears in OSC Routes at once and the status names it.
- Q: Does arming learn change the receiver or its limits? → A: No. Arming sets one flag in the dispatcher; routes, limits and the allow list are unchanged, and every message (including the captured one) is still dispatched normally (an unrouted address is counted as ignored).
- Q: Learn while OSC Routes is open and a value is being dragged? → A: Not applicable: OSC Routes has no value controls.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bind my controller's fader by moving it (Priority: P2)

A performer opens Settings › OSC › OSC Routes with the receiver on, taps Learn beside Glow intensity and
moves a fader on their tablet's OSC app, which sends `/1/fader3 0.42`. The status says "Glow intensity now
listens to /1/fader3." and a "Your alias" row `/1/fader3` appears. Moving the fader again changes the glow.

**Why this priority**: it is the roadmap row (P2).

**Independent Test**: a dispatcher with a fake clock and a learn session: a burst of three eligible
messages binds exactly the first address; a later message to it drives the parameter.

**Acceptance Scenarios**:

1. **Given** learn armed for Glow intensity, **When** `/1/fader3 0.42`, `/1/fader4 0.5`, `/1/fader3 0.9` arrive in one burst, **Then** exactly one alias `/1/fader3 → Glow intensity` exists and learn has ended.
2. **Given** that binding, **When** `/1/fader3 1.0` arrives, **Then** Glow intensity's live value is its maximum.
3. **Given** learn armed, **When** 10 s pass on the clock with no eligible message, **Then** learn ends with no binding and "timed out" is announced.
4. **Given** learn armed, **When** the user taps Cancel, **Then** learn ends with no binding.

### User Story 2 - Nothing else gets bound (Priority: P2)

**Acceptance Scenarios**:

1. **Given** the allow list on with only 192.168.1.20 approved, **When** 192.168.1.30 sends `/x 0.5` while learning, **Then** nothing is bound and learn keeps waiting.
2. **Given** learn armed, **When** `/fader 1` with a string argument, `/a*b 0.5` (pattern character), `/projectm/test 0.5` or a malformed datagram arrives, **Then** nothing is bound and learn keeps waiting.
3. **Given** the source over its rate limit, **When** an eligible message is rate-limited, **Then** it is not learned.

### Edge Cases

- The learned address is already a user alias of another parameter: moved; the status names the old parameter.
- The learned address already reaches the selected parameter: no change, "already controls".
- 16 aliases and a new address: learn ends, nothing bound, "No more aliases fit".
- The receiver stops while learning: learn ends with "stopped".
- A learn message inside a bundle: the first eligible message, depth-first.

## Requirements *(mandatory)*

- **OSC-004-R1**: OSC Routes MUST offer a Learn action for each routable parameter, with a status line and a Cancel action while learning.
- **OSC-004-R2**: Learn MUST start only while the receiver is listening; otherwise Learn is disabled with an explanation.
- **OSC-004-R3**: Learn MUST capture only a decoded message whose address passes OSC-003's alias rules, is outside `/projectm/`, and that has exactly one finite numeric argument (`f`, `i`, `h`, `d`).
- **OSC-004-R4**: A datagram refused by OSC-008's allow list MUST never be learned and MUST NOT approve its host.
- **OSC-004-R5**: Learn MUST record at most one address per session: the first eligible message in arrival order; later messages MUST NOT create another binding.
- **OSC-004-R6**: Learning MUST only create the route: the captured message is dispatched with the routes as they were when it arrived, so it never applies a value through the new route.
- **OSC-004-R7**: The captured address MUST be bound to the selected parameter as an OSC-003 user alias (enabled), replacing a user alias of the same address to another parameter; an address that already reaches the parameter is left unchanged; a full alias list ends learn without binding.
- **OSC-004-R8**: Learn MUST end after 10 s (injected monotonic clock) without a binding, and on Cancel; starting learn for another parameter restarts it; leaving OSC Routes cancels it.
- **OSC-004-R9**: Learn MUST end when the receiver stops listening.
- **OSC-004-R10**: Learn's start and every ending MUST be announced through the `.osc` announcement lane; traffic MUST NOT be announced.
- **OSC-004-R11**: Learn MUST store nothing but the alias: no peer address, no value, no new settings key.
- **OSC-004-R12**: OSC-009 rate limits MUST apply: a datagram refused by the limiter is never learned.

### Key Entities

- **Learn session**: the selected parameter and a deadline (memory only).
- **Learn capture**: the dispatcher's one-shot armed flag and the captured address.
- **Learned route**: a user alias `<address>=<parameter ID>`.

## Success Criteria *(mandatory)*

- **OSC-004-S1**: In a burst of eligible messages, exactly one address is bound (100% of runs of the acceptance test).
- **OSC-004-S2**: Disallowed peers, malformed datagrams, invalid addresses, non-numeric arguments and rate-limited datagrams never bind.
- **OSC-004-S3**: Without an eligible message, learn ends at 10 s on the clock with no binding.
- **OSC-004-S4**: A performer binds a controller address in 2 taps from OSC Routes plus one fader move.

## Assumptions

- One learn session at a time for OSC; it is independent of MIDI learn.
- The device check with a real LAN controller on D1 is a `{device}` task.
