# Research: MIDI-011 MIDI Hot-Plug Recovery

## MIDI-011-D1: Put enumeration and connect calls behind a protocol

- **Decision**: `MIDISourceSystem` with `snapshot() -> [MIDISourceSnapshot]` (every source and destination as the
  system lists them, each with a `UInt32` handle; 0 for destinations), `connect(_ handle:) -> Bool` and
  `disconnect(_ handle:)`. CoreMIDI's `MIDIEndpointRef` is a `UInt32`, so the handle is the ref itself.
- **Rationale**: the registry needs only these three calls; tests can then add, remove and re-add endpoints with
  changing handles and stable unique numbers, and count active connections (MIDI-011-R7).
- **Alternatives**: testing through `CoreMIDIInputProvider` with virtual sources — impossible on Linux and unreliable
  on the simulator; rejected.

## MIDI-011-D2: Registry keyed by stable ID, holding the current handle

- **Decision**: `[MIDIEndpointID: UInt32]`. IDs are assigned with MIDI-001's `MIDIEndpointIdentity.assign` over the
  snapshot's non-network records in enumeration order — exactly what discovery does — so the unique number is the key
  and a missing or shared number falls back to the name-based ID. A reconcile:
  1. builds the present sources (ID → handle, online flag);
  2. drops every entry whose source is absent, whose handle changed, whose handle was reported removed, or which is
     no longer wanted or no longer online: `disconnect(old handle)`; the first three count as **lost**;
  3. connects every wanted, present, online source without an entry: `connect(handle)`; on success the entry is stored,
     on failure nothing is stored (the next reconcile tries again).
- **Rationale**: an entry exists iff one connection is live, so no handle is connected twice (MIDI-011-R2). CoreMIDI may
  hand back a new ref or reuse the old one when a device returns (not documented for iOS; unknown behavior recorded per
  the constitution): a changed ref is caught by step 2, a reused ref by the removal mark (D3), and a disappearance seen
  only as absence from a snapshot by step 2.
- **Alternatives**: keying by ref (today's code) — a reused ref looks connected after CoreMIDI dropped the connection,
  and a new ref is not connected until discovery's list changes; rejected.

## MIDI-011-D3: Removal notifications mark handles

- **Decision**: the input's own client gets a notify block. `msgObjectRemoved` with a source child marks that handle
  removed and schedules a reconcile; `msgObjectAdded`, `msgSetupChanged` and `msgPropertyChanged` schedule one.
- **Rationale**: an unplug and replug inside one coalescing window can leave the snapshot identical (same ref, same
  ID); the mark still forces disconnect, a lost report and a fresh connect.
- **Alternatives**: relying on discovery's updates only — discovery reports nothing when its list is unchanged.

## MIDI-011-D4: Debounce with MIDI-001's coalescer on a serial queue

- **Decision**: `MIDIRefreshCoalescer` + `MIDIRefreshScheduler.serialQueue(label: "projectm.midi.input")`, 100 ms;
  every reconcile (scheduled or from `update(wanted:)`) runs under the subscriptions' `Mutex`, so two reconciles never
  interleave and CoreMIDI's notification thread only flips a flag and schedules.
- **Rationale**: one reconcile per burst with a bounded latency (MIDI-001-D3); tests use `ManualMIDIScheduler`.

## MIDI-011-D5: Reporting losses to the app

- **Decision**: a monotonically increasing `lossCount` (incremented once per reconcile that lost at least one endpoint)
  exposed through `MIDIInputProvider.sourceLossCount` (default 0 for providers without a registry) and
  `MIDIInputService.sourceLossCount`. `MIDIInputCoordinator.drain()` (main actor, ≤ 30 Hz) runs the state observers
  when it changed, before delivering the batch; `MIDIMappingCoordinator.releaseNotesIfInputChanged()` releases every
  held key when it changed — MIDI-008's existing release path.
- **Rationale**: no callback hops from CoreMIDI's or the queue's thread to the main actor; one atomic-ish read per
  drain.

## MIDI-011-D6: The DEBUG fake and the scripted system

- **Decision**: `ScriptedMIDISourceSystem` gives each plug a new handle, keeps a per-handle connection count (a second
  `connect` on a live handle makes it 2 and doubles delivery, so duplicates are observable), notifies removal and
  setup changes, simulates bursts, and `send(_:from:)` delivers once per live connection into the provider's ring.
  The app's DEBUG `-uitestFakeMIDI` uses it, and Plug/Unplug Fake Keys update both the discovery fake and it.
- **Rationale**: the acceptance asks for "one live listener per endpoint", so the fake must be able to show two.

## MIDI-011-D7: Reconnect announcement

- **Decision**: `MIDIDiscoveryCoordinator` keeps the IDs listed since discovery started (cleared when it stops); an
  appeared endpoint already seen is announced "MIDI device reconnected: <device>" (several: "N MIDI devices
  reconnected"), between the connected and disconnected sentences, on the `.midi` lane.
- **Rationale**: follows MIDI-001-D7's one-text-per-update pattern; nothing new is stored.
