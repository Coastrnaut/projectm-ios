# Feature Specification: OSC-006 OSC Bundles

**Feature Branch**: `feature/osc-006` (spec directory `278-osc-006-osc-bundles`)

**Created**: 2026-11-14

**Status**: Implemented (OSC-006-T11 {device} open)

**Input**: User description: "Implement roadmap row OSC-006 (OSC bundles) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Apply timestamped OSC bundles in order with
late-message policy." Acceptance, verbatim: "Two scheduled events execute in deterministic timestamp order."
P2, size L, depends on OSC-002 (integrated)."

Identifiers carry the roadmap ID: requirements `OSC-006-R1…`, success criteria `OSC-006-S1…`, research
decisions `OSC-006-D1…`, tasks `OSC-006-T01…`. FR-068 as amended on 2026-11-12 (ADR-0008, networking for
OSC) and every OSC-001, OSC-002, OSC-003, OSC-004, OSC-007, OSC-008 and OSC-009 requirement stay in force.
Network access is not widened: this row changes only *when* an already-received, already-decoded message is
applied. OSC-005 (send) is built in parallel and is out of scope here: no encoder or sender is added.

## Baseline: what exists today (audit of 2026-11-14, commit `8936ea3c`)

| Area | Today | Gap |
|---|---|---|
| Parser (OSC-002) | `OSCDecoder.decodePacket` decodes bundles (≤ 4 levels, ≤ 64 elements) with their NTP time tag (`OSCTimeTag`, `.immediately` = 1); a malformed element rejects the datagram | none |
| Dispatch (OSC-001, OSC-002) | `OSCDispatcher.handle` applies every message of a bundle at once, depth-first; the time tag is ignored | **gap**: no scheduling, no late policy |
| Receiver (OSC-001, OSC-007) | `OSCReceiver` lifecycle; `stop()` resets the limiter; the app stops it when the switch is off or the app leaves the foreground | **gap**: nothing to clear |
| Allow list (OSC-008) | checked per datagram in `OSCReceiver` before the dispatcher | none |
| Rate limits (OSC-009) | per source/global bucket before decoding; per target bucket per message with a deferred flush on `OSCFlushScheduler` and an injected `OSCMonotonicClock` | none: reused for the bundle wake-up |
| Routes, learn (OSC-003, OSC-004) | route lookup and learn capture in `OSCDispatcher.apply(message)` | none: scheduled messages go through it |
| App refresh (OSC-009-R11) | `onActivity` → `OSCRefreshGate` → one main-actor refresh ≤ 30 Hz reading live values | none: a scheduled apply reports activity |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: How is a time tag mapped to the device's clock? → A: At receipt, the dispatcher reads its monotonic clock and the wall clock once and maps the tag to `monotonic now + (tag − wall now)`. The mapping is made per datagram and stored as a monotonic due time, so a later wall-clock change never moves an already-scheduled message. Assumption: the sender's and the receiver's wall clocks are roughly in sync (both set automatically by the network); there is no offset setting in this row (OSC-006-R2).
- Q: What does time tag 1 mean? → A: "Immediately" (OSC 1.0): applied at receipt, like a message outside a bundle (OSC-006-R3).
- Q: Nested bundles? → A: Each message takes its innermost bundle's tag, but never earlier than any enclosing bundle's: an inner tag earlier than the outer one (including an inner "immediately") is treated as the outer tag (OSC 1.0 requires inner ≥ outer) (OSC-006-R4).
- Q: Order? → A: Messages apply in due-time order; equal due times keep arrival order (across datagrams), and within a datagram depth-first packet order (OSC-006-R5).
- Q: Late messages? → A: Fixed policy, not a user setting: up to 20 ms late is on time; 20 ms to 1 s late is applied at once and counted as late; more than 1 s late is dropped and counted (OSC-006-R6).
- Q: Far-future messages? → A: More than 10 s ahead is rejected (dropped and counted), not clamped: applying at a wrong time is worse than not applying (OSC-006-R7).
- Q: Pending limit? → A: At most 256 pending messages. A datagram whose future messages do not all fit drops all its future messages (the newest), counted; what is already scheduled is kept, so a flood cannot push out a performer's earlier cues (OSC-006-R8).
- Q: Rate limits, routes, learn? → A: The datagram-level limits (per source, global) and the allow list apply at receipt, before decoding, unchanged. Route lookup, policy, OSC-004 learn capture and the per-target limit apply when the message is dispatched at its due time, through the same path as an immediate message (OSC-006-R9).
- Q: Lifecycle? → A: The pending queue is cleared whenever the receiver stops or starts (switch off, background, port change) (OSC-006-R10).
- Q: UI? → A: None in this row; the counters are kept in memory with the others (OSC-006-R11).

### Session 2026-11-14 (speckit-clarify)

- Q: Are late, dropped and scheduled counts kept per bundle or per message? → A: Per message, like `applied` and `ignored` (OSC-001/002), so the counts add up; a bundle datagram still adds one to `bundles` (OSC-006-R11).
- Q: When a new datagram arrives while earlier scheduled messages are already due but their wake-up has not run yet, which goes first? → A: The due scheduled messages: every datagram first applies what is due, so a timer that fires a little late never reorders values (OSC-006-R5).
- Q: Does a malformed element still reject a bundle that also holds future messages? → A: Yes, unchanged from OSC-002: the whole datagram is rejected and nothing is scheduled.
- Q: Is the route of a scheduled message fixed at receipt? → A: No; the route table at the due time is used, so a route removed in between makes the message an unknown address (OSC-006-R9).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Cues land on the beat I scheduled (Priority: P2)

A performer's show computer sends OSC bundles stamped a little ahead of time so that changes land together
on a beat despite network jitter. Two bundles arrive in reverse order: one for t+20 ms setting glow to 0.8, one
for t+10 ms setting it to 0.2. projectM applies 0.2 at t+10 ms and 0.8 at t+20 ms.

**Why this priority**: it is the roadmap row (P2).

**Independent Test**: a dispatcher with fake clocks and a manual scheduler: nothing applies at receipt; at
t+10 ms the first value applies; at t+20 ms the second.

**Acceptance Scenarios**:

1. **Given** bundles tagged t+20 ms then t+10 ms arrive at t, **When** the clock reaches t+10 ms, **Then** only the t+10 ms value is applied; **when** it reaches t+20 ms, **Then** the t+20 ms value is applied.
2. **Given** two bundles with equal tags, **When** they become due, **Then** they apply in arrival order.
3. **Given** a bundle tagged "immediately", **When** it arrives, **Then** it applies at once.

### User Story 2 - Late and bogus timing is handled safely (Priority: P2)

**Acceptance Scenarios**:

1. **Given** a bundle 500 ms late, **When** it arrives, **Then** it is applied at once and counted as late.
2. **Given** a bundle 2 s late, **When** it arrives, **Then** nothing applies and it is counted as dropped.
3. **Given** a bundle 30 s ahead, **When** it arrives, **Then** nothing is scheduled and it is counted.
4. **Given** 256 pending messages, **When** another future bundle arrives, **Then** it is dropped and counted; the earlier ones still apply.
5. **Given** pending messages, **When** OSC is turned off, **Then** none of them apply later.

### Edge Cases

- An inner bundle tagged earlier than its outer bundle: uses the outer tag.
- A bundle mixing on-time and future messages: the on-time part applies now, the rest is scheduled.
- A scheduled message whose route was removed before it was due: ignored as an unknown address.
- A scheduled message whose target is over its rate: held and coalesced as in OSC-009.
- The wall clock changes after scheduling: due times do not move.

## Requirements *(mandatory)*

- **OSC-006-R1**: A bundle's messages MUST apply at their time tag's due time, not at receipt, unless the tag is "immediately" or already due.
- **OSC-006-R2**: A time tag MUST be mapped to the monotonic clock once, at receipt, using the wall clock read then; scheduled due times MUST NOT change afterwards.
- **OSC-006-R3**: Time tag 1 MUST apply at receipt.
- **OSC-006-R4**: A message's effective tag MUST be its bundle's tag, raised to the latest enclosing bundle's tag when earlier.
- **OSC-006-R5**: Messages MUST apply in effective-due order; ties MUST keep arrival order, and within a datagram depth-first packet order.
- **OSC-006-R6**: A message at most 20 ms late MUST apply at once; 20 ms to 1 s late MUST apply at once and be counted late; more than 1 s late MUST be dropped and counted.
- **OSC-006-R7**: A message due more than 10 s ahead MUST be dropped and counted, never clamped.
- **OSC-006-R8**: At most 256 messages MAY be pending; a datagram whose future messages do not all fit MUST have all of them dropped and counted.
- **OSC-006-R9**: A scheduled message MUST be dispatched through the same path as an immediate one (routes, policy, OSC-004 learn, OSC-009 per-target limit, live values); the OSC-008 allow list and OSC-009 datagram limits apply at receipt.
- **OSC-006-R10**: Stopping or starting the receiver MUST clear every pending message.
- **OSC-006-R11**: Counts of scheduled, late, late-dropped, beyond-horizon and overflow messages MUST be kept in memory with the receiver counters; no payload, peer or new settings key is stored.
- **OSC-006-R12**: Work per datagram MUST stay bounded (≤ 64 messages, logarithmic insertion); a scheduled apply MUST NOT run on the main thread or an audio thread.

### Key Entities

- **Time tag mapping**: monotonic now and wall now read at receipt.
- **Scheduled message**: a decoded message, its monotonic due time and an arrival sequence number (memory only).
- **Bundle schedule**: the bounded pending queue ordered by (due, sequence).
- **Bundle timing**: tolerance 20 ms, max lateness 1 s, horizon 10 s, capacity 256.

## Success Criteria *(mandatory)*

- **OSC-006-S1**: Two scheduled events received in reverse order execute in timestamp order at their due ticks in 100% of runs of the acceptance test.
- **OSC-006-S2**: Equal tags keep arrival order; nested bundles follow R4.
- **OSC-006-S3**: Late, far-future and overflow messages are applied or dropped exactly as R6-R8 say, and counted.
- **OSC-006-S4**: Over a real local listener, a bundle scheduled 200 ms ahead is never applied early and is applied within 1 s after its due time.
- **OSC-006-S5**: Turning OSC off leaves nothing pending.

## Assumptions

- Sender and receiver wall clocks are roughly synchronized; bundles from a badly skewed sender are dropped as late or far-future, which the counters show.
- NTP era rollover (2036) is handled by signed 32.32 differences; tags more than 68 years away are meaningless.
- The device check with a real LAN sender on D1 is a `{device}` task.
