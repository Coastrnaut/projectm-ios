# Research: OSC-009 OSC Rate Limiter

## OSC-009-D1: Algorithm

- **Decision**: token buckets in integer arithmetic. A bucket holds `tokens` in units of
  1/1,000,000,000 token (one token = 1e9 units), refilled by `rate × elapsed nanoseconds` up to
  `burst × 1e9`. Elapsed time is clamped to the time a full refill takes, so a jump of hours cannot
  overflow (`burst × 1e9 ≤ 1e12` for any burst ≤ 1,000). A clock that goes backwards refills nothing.
- **Rationale**: exact and deterministic (no floating point), O(1), steady rate plus bounded burst.
  Over any window of length W the bucket allows at most `burst + rate × W` takes.
- **Alternatives**: fixed-window counter — rejected: allows 2× rate across a window edge. Sliding
  log — rejected: memory grows with the rate.

## OSC-009-D2: Clock

- **Decision**: `OSCMonotonicClock`, a `@Sendable () -> UInt64` of nanoseconds. The default measures
  `ContinuousClock.now - origin` (Swift standard library, Linux-safe, monotonic); tests inject a fake.
- **Alternatives**: `Date` — rejected: wall clock, can jump. `DispatchTime` — rejected: Dispatch is not
  needed outside `OSCTransport/`.

## OSC-009-D3: Sources

- **Decision**: `OSCTransportEvent.datagram([UInt8], source: OSCSourceID = .unattributed)`. The
  network transport numbers each accepted peer connection (1, 2, 3, …; never an address). Fakes that
  omit the source share source 0.
- **Rationale**: the limiter never sees an address (OSC-001-R15), and existing call sites keep
  compiling through the default.

## OSC-009-D4: Order of checks and where they run

- **Decision**: in `OSCDispatcher.handle(_:source:)`, under the dispatcher's one lock:
  1. source and global buckets are refilled; the datagram passes only if both have a token, and only
     then are both taken (a source-limited datagram does not spend global tokens);
  2. if dropped: `rateLimited += 1`, no decode;
  3. otherwise decode (bounded by OSC-002), and for each message route → policy → one finite number →
     target bucket: a token → `store.setDouble` (applied), else hold (coalesced).
  Values are written to the store under the lock, so a deferred flush and a new datagram can never
  reorder writes to one target.
- **Consequence**: store observers run under the dispatcher's lock and MUST NOT call back into the
  dispatcher (the app's observer only signals the refresh gate). Documented in the contract.

## OSC-009-D5: Deferred flush

- **Decision**: `OSCFlushScheduler`, a `@Sendable (UInt64 delayNanoseconds, @escaping @Sendable () ->
  Void) -> Void`. The dispatcher keeps `flushScheduled`; when a value is held and no flush is
  scheduled, it schedules one for the earliest held target's next token. A flush applies every due
  held value and reschedules if values remain. The default scheduler is a detached `Task` that sleeps
  (`Task.sleep(nanoseconds:)`), pure Swift concurrency, off the main actor; tests use a manual
  scheduler driven by the fake clock.
- **Alternatives**: applying held values only when the next message arrives — rejected: the final
  value would be lost when a gesture ends. A Dispatch timer on the transport queue — rejected:
  more Network-folder code for no gain.

## OSC-009-D6: Numbers

| Limit | Rate | Burst | Why |
|---|---|---|---|
| per source | 200 datagrams/s | 50 | 2× a fast fader stream (~100 msg/s); burst covers a preset recall of many controls |
| global | 500 datagrams/s | 100 | bounds 8 flooding peers (1,600/s) to 500 decodes/s, each ≤1,472 bytes |
| per target | 60 updates/s | 10 | at most one change per frame on average at the 60 fps maximum |
| source table | 16 entries | — | 2× the transport's 8 peers |
| target table | 64 entries | — | well above today's 1 route; OSC-003 adds a few dozen |

Eviction is least-recently-used by a monotonically increasing use stamp; finding the victim scans at
most 64 entries, a bounded constant. An evicted target's held value is applied first.

## OSC-009-D7: Main-thread coalescing (render loop protection)

- **Decision**: `OSCRefreshGate` (pure, in PerformanceControl): `request(now:) -> UInt64?` returns
  nil when a refresh is already pending, else marks one pending and returns the delay until
  `lastRun + 1/30 s` (0 if already past); `begin(now:)` clears pending and records the run. The
  receiver exposes `onActivity` (called on the receiving side after every handled datagram, oversized
  or non-local drop, and flush). `OSCReceiverCoordinator` asks the gate and, only when it returns a
  delay, starts one main-actor task that sleeps the delay and refreshes state, test value and the
  rate-limited count.
- **Rationale**: at most one main-actor task pending and at most ~30 refreshes/s regardless of the
  flood; the latest state is read at refresh time, so nothing shown is stale for more than 1/30 s.
  The render loop is driven by the display link on the main thread; it never waits on OSC.
- **Alternatives**: one main-actor task per message (today) — rejected: unbounded main-thread work.
  A display-link-driven poll — rejected: couples Settings to the renderer.

## OSC-009-D8: Lifecycle

- **Decision**: `OSCReceiver` calls `dispatcher.resetLimits()` when it launches a transport and when it
  stops: tables cleared, held values discarded. Counters persist (OSC-001). A flush that fires after a
  reset finds nothing to apply.
