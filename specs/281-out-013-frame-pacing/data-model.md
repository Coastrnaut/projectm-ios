# Data Model: OUT-013 Frame Pacing per Output

## OutputPacingPolicy (value)

| Field | Type | Default | Rule |
|---|---|---|---|
| `maxFramesInFlight` | Int | 2 | clamped to 1…3 |
| `slowWaitFraction` | Double | 0.5 | a drawable wait longer than this fraction of the refresh interval arms the back-off |

## OutputPacingCounts (value, Equatable)

| Field | Meaning |
|---|---|
| `begun` | ticks that were allowed to render |
| `completed` | frames that left flight (GPU complete) |
| `droppedInFlight` | ticks refused because `maxFramesInFlight` frames were in flight |
| `droppedNoDrawable` | begun frames abandoned because no drawable came |
| `droppedBackOff` | ticks skipped by the slow-wait back-off |
| `inFlight` | frames in flight now (begun − completed − abandoned) |
| `maxInFlight` | the largest `inFlight` ever seen |
| `dropped` | derived: the three drop causes summed |

Invariant: `begun + droppedInFlight + droppedBackOff == ticks asked`; `0 ≤ inFlight ≤ maxFramesInFlight`.

## OutputFrameGate (reference, Sendable, lock-free)

State: atomics for every count, `inFlight`, and the back-off flag. Transitions:

- `tryBegin()` (frame thread): back-off armed → clear it, count `droppedBackOff`, false. `inFlight == max` → count
  `droppedInFlight`, false. Else `inFlight += 1` (compare-and-exchange), count `begun`, update `maxInFlight`, true.
- `complete()` (any thread): `inFlight -= 1` (never below 0), count `completed`.
- `abandon()` (frame thread, after a `tryBegin` that produced no frame): `inFlight -= 1`, count `droppedNoDrawable`.
- `noteDrawableWait(seconds, refreshInterval)`: arms the back-off when `seconds > slowWaitFraction × refreshInterval`.
- `counts` snapshot.
