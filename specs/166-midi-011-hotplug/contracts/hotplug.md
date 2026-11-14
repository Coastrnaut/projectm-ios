# Contract: MIDI-011 hot-plug recovery

## H1 `MIDISourceSystem` (PerformanceControl, pure)

```swift
public protocol MIDISourceSystem: AnyObject, Sendable {
    func snapshot() -> [MIDISourceSnapshot]
    func connect(_ handle: UInt32) -> Bool
    func disconnect(_ handle: UInt32)
}
```

## H2 `MIDISubscriptionRegistry.reconcile`

`mutating func reconcile(wanted: Set<MIDIEndpointID>, snapshot: [MIDISourceSnapshot], connect: (UInt32) -> Bool,
disconnect: (UInt32) -> Void) -> MIDIReconcileResult`

- IDs: `MIDIEndpointIdentity.assign` over the non-network records, enumeration order (same IDs as discovery).
- Post-condition: `entries` = { id ↦ handle | id wanted, present, online, connect succeeded now or earlier on that
  same handle without a removal in between }. `connect` is never called for a handle with a live entry.

## H3 `MIDISourceSubscriptions`

- `init(system:scheduler:coalescingDelayNanoseconds:)` (default 100 ms).
- `update(wanted:)` — reconcile now (caller's thread), opens the subscriptions.
- `setupChanged()` / `sourceRemoved(handle:)` — any thread; one coalesced reconcile; ignored while closed.
- `close()` — disconnect every entry; registry empty; closed.
- Read-only: `activeHandles: [MIDIEndpointID: UInt32]`, `connectCalls`, `disconnectCalls`, `reconcileCount`,
  `lossCount`, `absorbedSignals`.

## H4 Input provider and service

- `MIDIInputProvider.sourceLossCount: Int` (protocol requirement with a default of 0).
- `MIDIInputService.sourceLossCount` forwards it.
- `CoreMIDIInputProvider` and `ScriptedMIDISourceInputProvider` connect through `MIDISourceSubscriptions`.

## H5 App

- `MIDIInputCoordinator.drain()`: a changed `sourceLossCount` runs the state observers before the batch is delivered.
- `MIDIMappingCoordinator.releaseNotesIfInputChanged()`: a changed loss count releases every held key.
- `MIDIDiscoveryCoordinator.announcement(for:seen:)`: appeared IDs in `seen` → "MIDI device reconnected: <device>"
  (one) or "<n> MIDI devices reconnected" (several), after "connected" and before "disconnected" sentences.
