# Research: MIDI-001 MIDI Endpoint Discovery

Decisions by Claude under owner rule 4 (best judgement; conservative, local-first).

## MIDI-001-D1: Where MIDI lives

- **Decision**: `Packages/PerformanceControl`, pure core in `MIDI/`, system code in `MIDISystem/`
  under `#if canImport(CoreMIDI)`.
- **Rationale**: the package already names MIDI in its scope, hosts OSC with the same
  protocol-plus-fake split, runs in every CI loop (macOS host, iOS compile, Linux with
  `-DANALYSIS_NO_ACCELERATE`). CoreMIDI does not exist on Linux, so the guard keeps Linux green.
- **Alternatives**: a new `MIDIControl` package (more CI plumbing for no gain); app-only code (no
  Linux tests).

## MIDI-001-D2: The stable ID

- **Decision**: `MIDIEndpointID` is `system(Int32)` when the endpoint's `kMIDIPropertyUniqueID` is
  non-zero and no other endpoint in the same snapshot has it; otherwise
  `fallback(hash: UInt64, ordinal: Int)`, the hash an FNV-1a 64 over
  `direction|device|entity|endpoint name` (UTF-8, `|` separated), the ordinal counting identical
  hashes in enumeration order (0 first). A collision on the system number moves **every** endpoint
  sharing it to the fallback, so the rule does not depend on which one came first.
- **Rationale**: CoreMIDI documents the unique ID as the persistent identity of a MIDI object; USB
  class drivers keep a device in the saved setup (offline) when unplugged and give it the same IDs
  when it returns, while two units of one model get different IDs. Hashes are deterministic across
  launches (Swift's `Hasher` is seeded per process, so it is not used).
- **Risk (documented)**: the fallback is name-based: two identical devices without unique IDs can
  swap ordinals after a replug, and a rename changes a fallback ID. CoreMIDI assigns unique IDs to
  every object it creates, so the fallback should not occur; the endpoint exposes `id.isFallback`
  so MIDI-003/MIDI-012 can refuse to persist fallback IDs.
- **Alternatives**: `MIDIEndpointRef` (a per-session handle, not stable); names only (identical
  devices collide).

## MIDI-001-D3: Change notifications and coalescing

- **Decision**: the notify block of `MIDIClientCreateWithBlock` forwards one signal for
  `msgSetupChanged`, `msgObjectAdded`, `msgObjectRemoved` and `msgPropertyChanged`; discovery
  re-reads the whole list after a 100 ms delay and diffs. `MIDIRefreshCoalescer`: the first signal
  in a quiet period schedules one refresh; signals before it starts are absorbed; the refresh
  clears the pending flag before reading, so a signal during the read schedules the next.
- **Rationale**: a hub plugged in sends many added/property notifications; re-reading the full
  list is cheap (dozens of endpoints) and avoids parsing notification payloads. Refreshes run on
  one serial utility queue, so two never overlap.
- **Alternatives**: incremental updates from notification payloads (fragile; order of added vs
  property-changed varies); a trailing debounce that restarts on every signal (unbounded latency
  under a steady stream).

## MIDI-001-D4: Client lifetime and when discovery runs

- **Decision**: one client per provider, created on first start, kept for the process; stop only
  stops forwarding and clears the list. Discovery runs iff toggle on and app active (like
  OSC-001-R3).
- **Rationale**: Apple's CoreMIDI docs advise not disposing clients on iOS; keeping it idle costs
  nothing. Creating the client is the only system call that can fail (`unavailable(code)`).

## MIDI-001-D5: Network MIDI and Bluetooth

- **Decision**: no `MIDINetworkSession`/`MIDINetworkHost`/`MIDINetworkConnection`, no
  `CABTMIDICentralViewController`/`CABTMIDILocalPeripheralViewController`. Endpoints whose device
  driver owner is Apple's RTP-MIDI driver (`com.apple.AppleMIDIRTPDriver`) are attributed
  `network` and dropped from the list; Bluetooth driver (`com.apple.AppleMIDIBluetoothDriver`)
  endpoints are attributed `bluetooth` and listed (already connected by the system; no permission
  is needed to list them). Source and binary scans fail on the forbidden symbols.
- **Rationale**: FR-068 (ADR-0008) allows networking only in the OSC folder; pairing UI needs a
  Bluetooth usage string, which FILE-013's catalog would have to cover. The driver-owner strings are
  unverified on a device in this row (S8 records what a real controller reports).

## MIDI-001-D6: Persistence and privacy

- **Decision**: store only `settings.midi.enabled`; never log names (no `print`, `os_log` or
  diagnostics field); the list is dropped on stop.

## MIDI-001-D7: Announcements

- **Decision**: one text per update (not for the initial list) through a new
  `AnnouncementKind.midi` lane of the shared announcer (1 s window, repeat drop).
  Texts: one appeared "MIDI device connected: <name>"; one disappeared "MIDI device disconnected:
  <name>"; several "<n> MIDI devices connected" / "disconnected"; both kinds in one update join the
  two sentences with ". ". Endpoints are counted per name and direction pair collapsed by device
  name, so a controller with an input and an output is announced once ("Keys"), not twice.

## MIDI-001-D8: UI test stand-in

- **Decision**: `-uitestFakeMIDI` (DEBUG only) gives the coordinator a `ScriptedMIDIEndpointProvider`
  holding one virtual output "Fake Synth"; the MIDI section shows two buttons "Plug Fake Keys" /
  "Unplug Fake Keys" that add/remove a device with an input and an output (fixed unique IDs).
  The simulator has no hardware MIDI, and the real provider would show whatever the Mac exposes.
