# Data Model: SHOW-003

## CueStepRequest (PerformanceControl)

`next` | `previous` | `go(UUID)` — Hashable, Sendable.

## QuantizedCueStep (PerformanceControl, value type)

| Field | Meaning |
|---|---|
| `mode: QuantizeMode` | Off, Beat or Bar (Cue is stored as Off) |
| `beatsPerBar: UInt64` | 4 |
| `pending: Pending?` | `request`, `requestedAt`, `deadline` (monotonic ns), `timed` |

Transitions: empty → pending (request with a tempo); pending → empty (same request, `cancel()`, `setMode` to another
mode, `takeDue(at: t ≥ deadline)` which returns the request once); pending → pending (different manual request:
replaced, new deadline). A timed request on a pending slot changes nothing.

## Setting

`settings.show.quantizeCues`: `"beat"` or `"bar"`; absent = Off. Device-only; excluded from library backups; erased
with Settings.
