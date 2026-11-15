# Data Model: MIDI-010 MIDI Clock Receive

- **MIDIClockLane** (class, `@unchecked Sendable`): 256 preallocated `MIDIEvent` slots, atomic write/read indices,
  `dropped`, `isEnabled` (atomic Bool). `push` (producer, real-time safe, ignored while disabled), `drain(into:)`,
  `discardAll()`.
- **MIDIClockRules**: `pulsesPerQuarter` 24, `windowPulses` 96, `lockPulses` 24, `minimumBPM` 20, `maximumBPM` 300,
  `bpmAllowance` 0.1, `timeoutNanoseconds` 500 ms, `changeThreshold` 0.02, `outlierRatio` 0.6, `maximumGapPulses` 4.5,
  `outliersToRestart` 6, `acquireTolerance` 0.25.
- **MIDIClockStatus**: `noClock`, `acquiring`, `locked(bpm)`, `outOfRange(bpm)`, `stopped`.
- **MIDIClockTempo**: `bpm: Double`, `anchorNanoseconds: UInt64?`.
- **MIDIClockTracker** (struct): samples (pulse number, time) ≤ 96, fitted period, last pulse time, consecutive
  outliers, `position: Int?` (since Start), `pendingPosition: Int?` (Song Position), `isStopped`, `lastBeatPulse`.
  Inputs `receive(_ event:)` (clock/start/continue/stop/songPosition), `tick(now:)`, `reset()`. Outputs `status`,
  `tempo` (non-nil only when locked), `position`, `rejectedPulses`.
- **TempoOrigin.midiClock**, **TempoReadout.midiClock(bpm:)**, `TempoSource.updateMIDIClock(_ tempo: MIDIClockTempo?)`.
- **Stored**: `settings.midi.followClock` (Bool, absent = off).

State transitions: `noClock` → (first pulses) `acquiring` → (24 consistent pulses, in range) `locked` / `outOfRange`;
any → (0.5 s gap) `noClock`; any → (Stop) `stopped` → (Start/Continue + pulses) `acquiring`.
