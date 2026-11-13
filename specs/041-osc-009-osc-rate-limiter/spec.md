# Feature Specification: OSC-009 OSC Rate Limiter

**Feature Branch**: `feature/osc-009` (spec directory `041-osc-009-osc-rate-limiter`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement roadmap row OSC-009 (OSC rate limiter) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Bound high-rate control
messages per source and target." Acceptance, verbatim: "Flood fixture cannot starve render loop or
exceed configured rate." P0, effort M, depends on OSC-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `OSC-009-R1…`, success criteria `OSC-009-S1…`, tasks `OSC-009-T01…`. FR-068 as
amended on 2026-11-12 (ADR-0008, "Owner ruling: networking for OSC") and every OSC-001, OSC-002 and
OSC-007 requirement stay in force.

## Baseline: what exists today (audit of 2026-11-13, commit `f8069ae`)

| Part of the row | Today | Gap |
|---|---|---|
| Bound messages per source | The transport keeps at most 8 peers (OSC-001-R5) but delivers every datagram of every peer; datagram events do not say which peer sent them | **gap**: no per-source bound; the receiver cannot tell sources apart |
| Bound messages per target | Every well-formed `/projectm/test` message is applied to the parameter store at once | **gap**: no per-target bound |
| Work per datagram | Decoding is bounded (≤1,472 bytes, bundles ≤4 deep, ≤64 elements; OSC-002) | none for a single datagram; **gap** for the rate of datagrams |
| Render loop / main thread | Every applied change schedules one main-actor task in the app (`OSCReceiverCoordinator`) | **gap**: a flood schedules one main-thread task per message, which can starve the main thread and the frame loop |
| Traffic counters | received, applied, ignored, bundles, rejected, droppedNonLocal | **gap**: nothing counts limited traffic, and Settings shows no counter |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which limiting algorithm? → A: Token buckets with integer arithmetic on a monotonic clock injected by the caller (nanoseconds; never the wall clock), so the same input sequence always gives the same decisions. A token bucket gives a steady rate plus a bounded burst, which suits faders that send bursts while dragged; a fixed window allows twice the rate across a window edge (OSC-009-R1, R2).
- Q: What is a "source"? → A: One peer connection of the listener (one remote address and port), identified by an opaque number the transport assigns; the peer's address is never stored by the limiter (OSC-001-R15). Datagrams whose source is unknown share one "unattributed" source (OSC-009-R3).
- Q: What is a "target"? → A: One routed parameter (today only `osc.receiver.testValue`; OSC-003 adds more). Messages to unknown addresses are not targets: they are counted as ignored and never take a target slot (OSC-009-R4).
- Q: Which rates? → A: Per source 200 datagrams/s with a burst of 50; all sources together 500 datagrams/s with a burst of 100; per target 60 applied updates/s with a burst of 10. Controllers such as TouchOSC send roughly 30-100 messages/s per fader while dragged, so a normal user never meets the source limit; 60 updates/s matches the fastest frame rate the visualizer renders at (60 fps), so a target never changes more than once per frame on average; the global cap bounds the work of eight flooding peers (8 × 200 = 1,600/s) to 500 datagrams/s. The numbers are one configuration value with these defaults, so tests and later rows can set others (OSC-009-R1, R2, R5).
- Q: What happens to a datagram over the source or global rate? → A: It is dropped before decoding (so a flood costs no decoding work) and counted as `rateLimited` (OSC-009-R6).
- Q: What happens to an update over the target rate: coalesce or drop? → A: Coalesce. The newest value for that target is held (one slot per target, later values replace it) and applied at the target's next allowed slot, so the final state always equals the last value that passed the datagram limits; every held update is counted as `coalesced`. Dropping would leave a fader at a stale value when the user stops moving it (OSC-009-R7, R8).
- Q: How does a held value get applied when no more messages arrive? → A: The receiver schedules one deferred flush for the earliest due target (never more than one pending flush), run off the main thread on the receiver's side; the flush applies held values whose slot has come (OSC-009-R8).
- Q: How much memory may the limiter use? → A: Fixed caps: at most 16 source buckets (twice the transport's 8 peers, so recently cycled peers keep their state) with least-recently-used eviction; target buckets at most 64 with the same eviction, and an evicted target's held value is applied first so nothing is lost. Memory never grows with traffic (OSC-009-R9).
- Q: How is the render loop protected? → A: Two rules. (1) Per datagram, the transport side does bounded work: O(1) limiter checks, then at most one bounded decode and at most 64 applied messages; it never waits for the main thread. (2) The app copies OSC state onto the main thread at most about 30 times a second, however many messages arrive: one pending main-thread refresh at a time, started no sooner than 1/30 s after the previous one. 30 Hz is enough for a status line and a number in Settings and leaves the main thread's frame budget to rendering (OSC-009-R10, R11).
- Q: Where is limited traffic visible? → A: In Settings, under the OSC test value while OSC is on: "Rate-limited N", the number of datagrams dropped plus updates coalesced since the listener started. Counters are in memory only and hold no payloads or addresses (OSC-009-R12).
- Q: Is an ADR needed? → A: No. No default is overridden; the limiter is inside OSC-001's receiver and ADR-0008's ruling.

### Session 2026-11-13 (speckit-clarify)

Same delegation (owner rule 4); recommended option taken each time.

- Q: Can the user change the rates in Settings? → A: No (recommended: fewer controls, and a user raising them would defeat the safety bound). The rates are fixed app defaults; only tests and later rows set others (OSC-009-R5).
- Q: What happens to the buckets when the listener stops and starts again? → A: Every start begins with fresh, full buckets and no held values, so a restart never inherits a previous session's debt; a stop discards held values (OSC-009-R8, edge cases).
- Q: Does "Rate-limited N" count since the app launched or since the listener started? → A: Since the receiver was created (app launch), like OSC-001's other counters, which also survive restarts; the number only grows during a session and is never stored (OSC-009-R12).
- Q: When OSC-006 schedules timestamped bundle messages, which limit applies? → A: The datagram limits apply when the bundle arrives; each scheduled message passes the target limiter when it becomes due, so scheduling can never bypass the target rate. Recorded for OSC-006; nothing is scheduled in this row (Assumptions).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A flooding controller cannot freeze the visualizer (Priority: P1)

A performer's controller (or a misbehaving app on the same Wi-Fi) sends thousands of OSC messages a
second. The visualizer keeps rendering smoothly and the app stays responsive; the excess messages
are dropped or merged.

**Why this priority**: the roadmap's acceptance criterion; a P0 safety bound for a live show.

**Independent Test**: a flood fixture pushes 100,000 datagrams from three sources through the
receiver with a fake clock; applied updates never exceed the configured rate in any window, the
work done is bounded, and the app's main thread is refreshed at most about 30 times a second.

**Acceptance Scenarios**:

1. **Given** OSC is listening, **When** a source sends far above 200 datagrams/s, **Then** at most
   the configured rate (plus the burst) is decoded and the rest is counted as rate-limited.
2. **Given** several sources flood together, **When** their total is above 500 datagrams/s,
   **Then** at most the global rate is decoded.
3. **Given** a flood of updates to one target, **When** they arrive, **Then** the target changes at
   most 60 times a second (plus the burst) and the main thread is refreshed at most about 30 times a
   second.

---

### User Story 2 - The last value always wins (Priority: P1)

A performer sweeps a fader quickly and stops. The parameter ends at the fader's final value, even
though intermediate values were merged.

**Why this priority**: dropping would leave stale values after a fast gesture.

**Independent Test**: limiter and flood tests assert that the final applied value equals the last
value sent, including when the last value arrived over the rate.

**Acceptance Scenarios**:

1. **Given** a target is over its rate, **When** new values arrive, **Then** only the newest is held
   and it is applied at the next allowed slot, without needing another message.

---

### User Story 3 - See that limiting happened (Priority: P2)

A user checking their controller sees "Rate-limited N" in Settings, so a controller that sends too
fast is explained rather than mysterious.

**Independent Test**: unit test of the counter and text; a UI test shows the row while OSC is on.

**Acceptance Scenarios**:

1. **Given** OSC is on, **When** the user opens Settings, **Then** the OSC section shows
   "Rate-limited 0" (or the current count).

### Edge Cases

- A clock that does not advance (all datagrams at one instant): only the burst passes.
- A clock jump of hours: buckets refill to their burst, never beyond, and arithmetic cannot
  overflow.
- More sources than the bucket table holds: least recently used sources are evicted; the global cap
  still bounds the total.
- A bundle of 64 messages: counts as one datagram at the source and global limits; each message is
  one update at its target.
- A rate-limited datagram that would have been malformed: it is not decoded, so it counts as
  rate-limited, not rejected.
- The listener stops while a value is held: the held value is discarded and nothing is applied
  after the stop; counters persist for the receiver's life, like OSC-001's.

## Requirements *(mandatory)*

### Functional Requirements

- **OSC-009-R1**: The receiver MUST limit decoded datagrams per source to a configured rate and
  burst (defaults 200/s, burst 50), with decisions computed from an injected monotonic clock.
- **OSC-009-R2**: The receiver MUST limit decoded datagrams from all sources together to a
  configured rate and burst (defaults 500/s, burst 100).
- **OSC-009-R3**: The transport MUST tag each datagram with an opaque source number per peer
  connection; the limiter MUST NOT store peer addresses. Untagged datagrams share one source.
- **OSC-009-R4**: Only messages that would be applied to a routed parameter MUST count against that
  target's limit; ignored and rejected messages MUST NOT take target slots.
- **OSC-009-R5**: Rates, bursts and table sizes MUST be one configuration value with the defaults
  above, settable by tests and not shown in Settings. Each listener start MUST begin with empty
  bucket tables (full buckets) and no held values.
- **OSC-009-R6**: A datagram over the source or global limit MUST be dropped before decoding and
  counted as `rateLimited`.
- **OSC-009-R7**: Updates to one target MUST be applied at most at the configured target rate and
  burst (defaults 60/s, burst 10).
- **OSC-009-R8**: An update over its target's rate MUST be held (newest replaces older; every held
  update counted as `coalesced`) and applied at the target's next allowed slot by a deferred flush, so the final
  applied value equals the last value accepted; at most one flush MUST be pending at a time.
- **OSC-009-R9**: Limiter memory MUST be bounded: at most 16 source buckets and 64 target buckets,
  least recently used evicted; an evicted target's held value MUST be applied before eviction.
- **OSC-009-R10**: Work per datagram on the receiving side MUST be bounded (constant-time limiter
  checks, at most one bounded decode, at most 64 message applications) and MUST never wait on the
  main thread.
- **OSC-009-R11**: The app MUST copy OSC state onto the main thread at most once per 1/30 s, with at
  most one refresh pending, however many changes arrive; the latest state MUST still be shown.
- **OSC-009-R12**: Settings MUST show "Rate-limited N" (datagrams dropped plus updates coalesced)
  under the test value while OSC is on, counted since the receiver was created; counters MUST stay
  in memory and hold no payloads or addresses.

### Key Entities

- **Rate limit configuration**: per-source, global and per-target rate and burst; table caps.
- **Token bucket**: tokens available and last refill time for one source, the global stream or one
  target.
- **Held update**: the newest value waiting for its target's next slot.
- **Counters**: OSC-001's counters plus `rateLimited` and `coalesced`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **OSC-009-S1**: In the flood fixture (100,000 datagrams from 3 sources, clock advancing 1 ms per
  50 datagrams), applied updates to the target never exceed burst + rate × window length in any
  window, and decoded datagrams never exceed the global allowance.
- **OSC-009-S2**: In the flood fixture, the final applied value equals the last value that passed
  the datagram limits (a datagram dropped at the source or global limit carries no value), and a
  value sent after the flood ends is applied.
- **OSC-009-S3**: In the flood fixture, the work done is bounded by counts: decoded datagrams ≤ the
  global allowance for the fixture's simulated duration, and every other datagram costs only the
  limiter's constant-time check.
- **OSC-009-S4**: The app never has more than one main-thread refresh pending, however many changes
  arrive (a flood of 10,000 changes), and refreshes start at most 30 times per second of (simulated)
  time plus one.
- **OSC-009-S5**: The OSC-001 loopback integration test and every existing OSC test still pass.

## Assumptions

- The visualizer renders at up to 60 fps; the render loop is fed by the main thread's display link,
  so protecting the main thread protects the render loop.
- OSC-003 (routes), OSC-006 (timestamped bundles) and OSC-008 (allowlist) fit in front of or behind
  the limiter: the allowlist drops before the limiter, routes define targets, and scheduled bundle
  messages pass through the target limiter when they become due.
- The device LAN check is a `{device}` task, run last, not by this feature's agent.
