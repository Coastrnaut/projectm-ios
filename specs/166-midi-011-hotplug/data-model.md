# Data Model: MIDI-011 MIDI Hot-Plug Recovery

All in memory; nothing stored or logged.

| Entity | Fields | Rules |
|---|---|---|
| `MIDISourceSnapshot` | `handle: UInt32` (0 for destinations), `record: MIDIEndpointRecord` | One per endpoint the system lists, in enumeration order. |
| `MIDISubscriptionRegistry` | `entries: [MIDIEndpointID: UInt32]`, `removed: Set<UInt32>` | An entry exists iff exactly one connection to that handle is live. `removed` is cleared by every reconcile. |
| `MIDIReconcileResult` | `connected: [MIDIEndpointID]`, `disconnected: [MIDIEndpointID]`, `lost: Set<MIDIEndpointID>` | `lost` ⊆ `disconnected`: the endpoint was absent, its handle changed or was reported removed. |
| `MIDISourceSubscriptions` | registry, `wanted: Set<MIDIEndpointID>`, `isOpen`, coalescer, counters (`connectCalls`, `disconnectCalls`, `reconcileCount`, `lossCount`) | `update(wanted:)` reconciles at once; `setupChanged()` / `sourceRemoved(handle:)` reconcile once per burst; `close()` disconnects all and ignores later scheduled reconciles until the next `update`. |

## State transitions (one endpoint, wanted)

```text
absent ──appears──▶ connected(handle h)
connected(h) ──removed / absent──▶ absent            (disconnect h, lost)
connected(h) ──returns as h'≠h──▶ connected(h')      (disconnect h, lost, connect h')
connected(h) ──removed mark, returns as h──▶ connected(h)  (disconnect h, lost, connect h)
connected(h) ──unwanted or offline──▶ idle           (disconnect h, not lost)
any ──close──▶ idle                                  (disconnect, registry empty)
```
