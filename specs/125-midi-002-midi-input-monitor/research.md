# Research: MIDI-002 MIDI Input Monitor

Decisions by Claude under owner rules 4 and 9 (2026-11-14).

## MIDI-002-D1 Receive Universal MIDI Packets with the MIDI 1.0 protocol

- **Decision**: one input port from `MIDIInputPortCreateWithProtocol(client, name, ._1_0, &port,
  receiveBlock)`; the block receives a `MIDIEventList` of UMP words. Decode message type 0x1
  (system common and real-time, 1 word), 0x2 (MIDI 1.0 channel voice, 1 word: status, data 1,
  data 2) and 0x3 (SysEx7, 2 words: status nibble complete/start/continue/end and a byte count;
  lengths are summed, contents dropped). Every other type is skipped by its word count (0, 1, 2,
  6, 7: 1 word; 3, 4, 8, 9, 10: 2; 11, 12: 3; 5, 13, 14, 15: 4) so a stray MIDI 2.0 packet never
  desynchronizes the walk. A zero packet timestamp means "now".
- **Rationale**: the packet-list API (`MIDIInputPortCreateWithBlock`, `MIDIPacketList`) is
  deprecated since iOS 14; the event-list API is current. With the 1.0 protocol the system
  converts any MIDI 2.0 source to MIDI 1.0 channel voice words, and running status is already
  resolved, so the callback decodes fixed-size words with no state except SysEx length.
- **Alternatives**: the legacy packet list (deprecated, byte streams with running status in the
  callback); the 2.0 protocol (32-bit values that MIDI-004's 7-bit scaling does not need yet).

## MIDI-002-D2 Keep a byte-stream parser too

- **Decision**: `MIDIByteStreamParser` (running status, real-time bytes inside messages leave the
  partial message untouched, system common cancels running status, SysEx counted until F7 or the
  next non-real-time status, stray data bytes ignored). The scripted provider injects bytes, so
  tests and the UI stand-in use the encoding people read in MIDI documentation.
- **Rationale**: it is small, pure and table-tested, and it keeps a path for any byte source.

## MIDI-002-D3 A preallocated SPSC ring of 512 events, drop newest

- **Decision**: `MIDIEventRing` stores `MIDIEvent` values (16 bytes) in an
  `UnsafeMutablePointer` allocated once; `Atomic<Int>` write and read counters; the producer
  checks free space against the read counter and, when full, drops the event and increments
  `dropped`. Timing clock and active sensing increment their own atomic counters and are never
  stored. The consumer drains up to a limit; `discardAll()` (consumer side) moves the read index to
  the write index.
- **Single producer**: CoreMIDI calls one port's receive block on its own high-priority thread,
  one call at a time; the scripted provider is called from one thread in tests and from the main
  thread in the UI stand-in, never both at once (the stand-in replaces the system provider).
- **No allocation check**: the existing VIS-003 pattern: the ring's storage address and capacity
  are unchanged after 10,000 messages through the callback path (decode into the ring), and the
  decode functions take `UnsafeBufferPointer`s and a ring reference (no arrays, strings or
  closures on the path).
- **Alternatives**: drop-oldest (the producer would have to advance the consumer's index with CAS,
  as AudioCore's ring does; for a monitor the newest-loss case is a flood a person cannot read
  anyway, and it is counted); a lock (constitution VII).

## MIDI-002-D4 Source connection without identifiers in messages

- **Decision**: `connect(sources:)` takes MIDI-001 IDs; the CoreMIDI provider re-enumerates
  sources and destinations, rebuilds records exactly like `CoreMIDIEndpointProvider`, assigns IDs
  with `MIDIEndpointIdentity` over the non-network records and connects the sources whose ID is
  requested; previously connected endpoints not requested are disconnected. `connRefCon` is nil,
  so the receive block cannot know which source sent a word, and `MIDIEvent` has no source field.
- **Rationale**: the row's acceptance is "without recording identifiers"; the cheapest proof is
  that the message path never carries one.

## MIDI-002-D5 One shared input, drained at display rate

- **Decision**: `MIDIInputCoordinator` in the app owns the service and a set of named clients;
  MIDI-003 learn will register a second client. While receiving, a `CADisplayLink`
  (`preferredFrameRateRange` 15–30 Hz) drains up to 512 events per tick on the main actor and
  passes the batch to every client. Tests call `drain()` directly with an injected clock.
- **Rationale**: one port and one ring per process (a second port would double CoreMIDI work and
  break single-consumer use); display-rate draining matches what can be shown.
- **Alternatives**: a port per feature; a dispatch timer (not tied to the display).

## MIDI-002-D6 Privacy definition and its test

- **Definition**: "identifiers" are a MIDI endpoint's system unique number (decimal or hex), its
  MIDI-001 ID text (`midi:<n>`, `midi-fb:…`), its display, endpoint, entity or device name, and
  which source sent a message. "Recording" is keeping them in a monitor entry, counter, status
  text, diagnostic (the input state), the app's log, or UserDefaults.
- **Test**: the app acceptance test plugs a fake source "Secret Keys" (unique number 0x5EC2E7),
  injects CC and notes, then scans: every entry's texts and its `String(reflecting:)` dump, the
  counters and status text, the input state, every key and value of the test's UserDefaults suite
  and of the standard domain, and the current process's unified log entries since the test began
  (`OSLogStore(scope: .currentProcessIdentifier)`). None may contain "Secret", "5EC2E7" (any case),
  "6210279" or "midi:6210279".

## MIDI-002-D7 Announcements

- **Decision**: none for live traffic (spec Clarifications). The new files are added to
  `check_status_events.py`'s list so a direct post would fail the check.
