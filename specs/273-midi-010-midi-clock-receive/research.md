# Research: MIDI-010 MIDI Clock Receive

- **MIDI-010-D1 Decoding is already done.** MIDI-002's `MIDIUMPDecoder` handles UMP type 0x1 (status ≥ 0xF8 →
  `MIDIEvent.realTime`, 0xF2 → `.songPosition`) and `MIDIByteStreamParser` handles real-time bytes inside running
  status. The CoreMIDI input converts packet host time to monotonic nanoseconds (0 → arrival). Decision: reuse; add
  only decoder tests for the clock words. Alternative (a second decoder) rejected: duplicate code.
- **MIDI-010-D2 Getting pulse timestamps to the main actor.** The ring counts clocks (MIDI-002-R4) so the monitor and
  other clients never see 24–120 pulses per second. Options: (a) store clocks in the ring — changes what every client
  sees and fills the 512 slots; (b) a side queue of pulse timestamps only — loses ordering against Start/Stop, which
  live in the ring and are drained separately; (c) a side lane holding clock **and** start/continue/stop/song
  position, filled by the same producer in order. Decision: (c), `MIDIClockLane`, 256 events (2 s at 300 BPM; the
  drain runs at 30 Hz), drop newest on overflow with a counter, enabled by an atomic flag so nothing is copied while
  no one follows. One hook line in `MIDIEventRing.push`; the ring's behaviour for other clients is unchanged.
- **MIDI-010-D3 BPM estimator.** Mean interval = (last − first)/n is exposed to the end points' jitter; the
  least-squares slope of time against pulse number over 96 pulses has a standard error of σ/√(Σ(x−x̄)²) ≈ σ/271:
  ±1 ms uniform jitter (σ ≈ 0.58 ms) gives ≈ 0.002 ms on a 20.8 ms period (≈ 0.01 % at 120 BPM). Decision: least
  squares over the last 96 pulses (pulse numbers include counted gaps), lock after 24 pulses.
- **MIDI-010-D4 Outliers and gaps.** Against the fitted period p: interval < 0.6p → outlier, ignored (duplicate or
  spurious pulse); k = round(interval/p) for 0.6p ≤ interval < 4.5p → k pulses (k − 1 dropped, counted so the beat
  position stays right); ≥ 4.5p → acquisition restarts. Six consecutive outliers restart acquisition (tempo doubled).
  During acquisition (no period yet) an interval more than 25 % from the previous one restarts the window.
- **MIDI-010-D5 Tempo changes.** A step change: when the fit over the last 24 pulses differs from the full window's
  by more than 2 %, the window is cut to those 24. Jitter cannot trigger it (a 24-pulse fit's error is ≈ 0.1 % at
  300 BPM with ±1 ms). A 120 → 140 step settles within ~2 beats.
- **MIDI-010-D6 Loss, transport and phase.** Lost after 0.5 s without a pulse (at 20 BPM a pulse is 125 ms, so four
  missing pulses) or on Stop; after Stop the clock does not set the tempo until Start/Continue; pulses meanwhile keep the measurement warm but do not move the position. Start: next pulse is position 0.
  Song Position (sixteenths × 6 pulses) before Continue: the next pulse is that position; Continue without it: the
  position continues. Anchor: the fitted time of the latest pulse whose position is a multiple of 24 (fitted, so
  jitter does not move the grid). No Start/Continue seen: no anchor (BPM only). Range 20–300 BPM with 0.1 allowance.
- **MIDI-010-D7 Priority.** `TempoSource.snapshot`: locked clock → `.midiClock` (confidence 1); else manual; else
  estimate. Taps continue to build a manual tempo underneath, so losing the clock falls back to it. SHOW-011's
  hand-off foresaw this ("another override kind beside manual"). Alternative (tap outranks clock) rejected: a
  performer following a DAW expects the DAW to lead; the notice explains why a tap did nothing.
- **MIDI-010-D8 Timeout without input.** The input coordinator calls clients only when something arrives, so the
  coordinator runs a 100 ms main-actor task while following (cancelled when off) that calls `tick(now:)`; tests call
  `tick` with an injected clock.
- **MIDI-010-D9 UI-test fake.** The fake panel's "Fake Clock 120" toggle runs a 10 ms main-actor timer that sends every
  pulse due on a 120 BPM grid (timestamps on the grid, so the reading is exact) through the fake input.
