# Data Model: MIDI-001 MIDI Endpoint Discovery

All types are in-memory values in `PerformanceControl` (pure Swift, `Sendable`), except the
toggle. Nothing below is stored except `settings.midi.enabled`.

## MIDIEndpointDirection

`source` (shown "Input": messages come from it) | `destination` (shown "Output").

## MIDIEndpointTransport

`local` (USB, virtual, anything not attributed) | `bluetooth` | `network` (dropped from the list,
MIDI-001-R2). Derived from the device's driver owner (research MIDI-001-D5).

## MIDIEndpointRecord (what a provider reads)

| Field | Type | Notes |
|---|---|---|
| uniqueID | Int32 | system unique number; 0 when missing |
| direction | MIDIEndpointDirection | |
| displayName | String | may be empty |
| endpointName, entityName, deviceName | String | for the fallback ID only; empty when absent |
| isOffline | Bool | |
| isVirtual | Bool | no entity behind the endpoint |
| transport | MIDIEndpointTransport | |

## MIDIEndpointID

`unique(Int32)` | `fallback(hash: UInt64, ordinal: Int)`; `isFallback`; `description`
`"midi:<n>"` or `"midi-fb:<16 hex>-<ordinal>"`. Rule: research MIDI-001-D2.

## MIDIEndpoint

`id`, `direction`, `name` (display name, or "MIDI input"/"MIDI output" when empty), `isOnline`,
`isVirtual`, `transport`, `deviceName` (for grouping announcements; never stored).

## MIDIEndpointList

`endpoints: [MIDIEndpoint]` ordered inputs, then outputs, by case-insensitive name, then ID
description; `make(from: [MIDIEndpointRecord])` drops network endpoints, assigns IDs and sorts;
`displayNames: [MIDIEndpointID: String]` appends " (2)", " (3)"… to the 2nd, 3rd… endpoint with the
same direction and name, in list order.

## MIDIEndpointChange

`appeared(MIDIEndpoint)` | `disappeared(MIDIEndpoint)` | `renamed(id, from: String, to: String)` |
`onlineChanged(id, isOnline: Bool)`. Order: disappeared (old list order), appeared, renamed,
online changed (new list order).

## MIDIDiscoveryState

`off` | `listening` | `unavailable(code: Int32)`. Listening carries the current list in
`MIDIDiscoveryUpdate`.

## MIDIDiscoveryUpdate

`endpoints: MIDIEndpointList`, `changes: [MIDIEndpointChange]`, `isInitial: Bool` (the first list
after a start; changes are then all `appeared` and are not announced).

## Lifecycle (MIDIEndpointDiscovery)

```text
off --start()--> provider.start ok --> listening (initial refresh scheduled, delay 0)
off --start()--> provider.start fails --> unavailable(code)   (no retry; stop() → off)
listening --signal--> refresh scheduled (one per burst, 100 ms) --> update (if changes)
listening --stop()--> off (provider stops forwarding; list cleared; pending refresh ignored by generation)
```

## Toggle

`AppSettings.midiEnabled`, key `settings.midi.enabled`, default `false`.
