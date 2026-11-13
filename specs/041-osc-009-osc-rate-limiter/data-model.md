# Data Model: OSC-009 OSC Rate Limiter

All types are in memory only and hold no payloads or peer addresses.

## OSCRateLimit

| Field | Type | Rule |
|---|---|---|
| `perSecond` | Int | ≥ 1 |
| `burst` | Int | 1…1,000 |

## OSCRateLimitConfiguration

| Field | Default |
|---|---|
| `perSource` | 200/s, burst 50 |
| `global` | 500/s, burst 100 |
| `perTarget` | 60/s, burst 10 |
| `maximumSources` | 16 |
| `maximumTargets` | 64 |

`OSCRateLimitConfiguration.default`; tests may pass others (OSC-009-R5).

## OSCTokenBucket

`tokens` (UInt64 units, 1 token = 1e9), `lastRefill` (ns). Starts full. Operations: `refill(now:)`,
`hasToken`, `take()`, `nanosecondsUntilToken`.

## OSCSourceID

`rawValue: UInt64`; `.unattributed` = 0. Assigned by the transport per peer connection.

## OSCRateLimiter

Source table (≤ `maximumSources`), global bucket, target table (≤ `maximumTargets`, each entry a
bucket and an optional held `Double`). Operations: `admitDatagram(from:now:) -> Bool`,
`submit(_:to:now:) -> .applyNow | .held`, `takeDue(now:) -> [(ParameterID, Double)]`,
`nextDue(now:) -> UInt64?` (delay), `reset()`.

State per target: *idle* (no held value) → *holding* (value held, waiting for a token) → *idle* when
the flush applies it, a newer value is applied directly, the target is evicted (value applied first),
or `reset()` discards it.

## OSCReceiverCounters (extended)

| New field | Meaning |
|---|---|
| `rateLimited` | datagrams dropped at the source or global limit (not decoded) |
| `coalesced` | messages held for a target's next slot instead of applied at once |

Settings shows `rateLimited + coalesced` as "Rate-limited N".

## OSCRefreshGate

`pending: Bool`, `lastRun: UInt64?`, `interval` (default 33,333,333 ns = 1/30 s).
