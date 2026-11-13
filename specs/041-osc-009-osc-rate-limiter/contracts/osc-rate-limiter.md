# Contract: OSC rate limiter (OSC-009)

## L1 — Limiter (pure, `PerformanceControl/OSC/OSCRateLimiter.swift`)

- `admitDatagram(from source: OSCSourceID, now: UInt64) -> Bool`: true takes one token from the
  source's bucket and one from the global bucket; false takes none (OSC-009-R1, R2, R6).
- `submit(_ value: Double, to target: ParameterID, now: UInt64) -> OSCTargetDecision`:
  `.applyNow` takes one token from the target and discards any held value (it is older);
  `.held` stores the value as the target's only held value (OSC-009-R7, R8).
- `takeDue(now:) -> [(ParameterID, Double)]`: every held value whose target has a token; takes it.
- `nextDue(now:) -> UInt64?`: nanoseconds until the earliest held value can be applied; nil if none.
- Tables never exceed their caps; inserting into a full table evicts the least recently used entry;
  an evicted target's held value is returned for application (`evicted` output) (OSC-009-R9).
- Every operation is O(1) apart from eviction, which scans at most the table cap.

## L2 — Dispatcher (`OSCDispatcher`)

- `init(store:routes:limits:clock:scheduleFlush:)`; defaults: `.default`, the continuous clock, a
  `Task.sleep` scheduler.
- `handle(_ datagram: [UInt8], source: OSCSourceID = .unattributed) -> OSCDispatchOutcome`, with new
  outcomes `.rateLimited` (datagram) and `.coalesced(ParameterID)` (per message).
- `flush()`: applies due held values; schedules the next flush if values remain. At most one flush is
  scheduled at a time.
- `resetLimits()`: clears the limiter (held values discarded); counters stay.
- Store writes happen under the dispatcher's lock; store observers MUST NOT call back into the
  dispatcher or the receiver's counters.

## L3 — Receiver (`OSCReceiver`)

- `init(store:routes:limits:clock:scheduleFlush:makeTransport:)`.
- Calls `resetLimits()` on every launch and stop (OSC-009-R5).
- `onActivity(_:)`: handler called on the receiving side after every datagram, drop and flush.

## L4 — Transport

- `.datagram([UInt8], source: OSCSourceID = .unattributed)`; `NetworkDatagramTransport` numbers each
  accepted peer connection from 1.

## L5 — App (`OSCReceiverCoordinator`)

- Activity → `OSCRefreshGate.request(now:)`; a non-nil delay starts one main-actor task that sleeps the
  delay, calls `begin(now:)` and refreshes `state`, `testValue`, `rateLimitedCount` (OSC-009-R11).
- Settings: `LabeledContent("Rate-limited", value: "N")`, identifier `oscRateLimited`, shown while
  OSC is on (OSC-009-R12).
