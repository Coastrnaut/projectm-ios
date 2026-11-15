# Contract: MIDI-010 MIDI Clock

## C1 Lane (package)
- `MIDIEventRing.clockLane: MIDIClockLane`. `push` copies `.clock`, `.start`, `.continue`, `.stop`, `.songPosition`
  into the lane when enabled, in arrival order, then behaves exactly as before (clock counted, others stored).
- `MIDIClockLane.isEnabled` (set by the consumer), `drain(into:maxCount:)`, `discardAll()`, `dropped`.

## C2 Tracker (package, pure)
- `MIDIClockTracker(rules:)`; `receive(_ event: MIDIEvent)`; `tick(now: UInt64)`; `reset()`.
- `status: MIDIClockStatus`; `tempo: MIDIClockTempo?` (locked only); `position: Int?`; `rejectedPulses: Int`.
- BPM = 60e9 / (24 × fitted period ns), least squares over ≤ 96 pulses; rules in data-model.md.

## C3 Tempo source (package)
- `TempoSource.updateMIDIClock(_:)`; `snapshot` = `.midiClock` (confidence 1, the clock's anchor) when set, else
  manual, else estimate. `TempoReadout(snapshot:indicator:)` → `.midiClock(bpm:)` for that origin.

## C4 App
- `MIDIClockCoordinator.followKey = "settings.midi.followClock"`; `isFollowing`, `setFollowing(_:)`, `status`,
  `statusText` ("MIDI clock: 120.0 BPM", "MIDI clock: measuring", "MIDI clock: stopped", "MIDI clock: out of range", "No MIDI clock",
  "Turn on Listen for MIDI devices"), `tick()`.
- Identifiers: toggle `midiFollowClockToggle`, status `midiClockStatus`; DEBUG `midiFakeClockToggle`.
- Readout: state "MIDI clock", spoken "<n> BPM, MIDI clock"; scene HUD source "MIDI clock"; tap notice "MIDI clock is
  setting the tempo".
