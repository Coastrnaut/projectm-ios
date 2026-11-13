# Research: SHOW-011 Tap Tempo

Decisions taken under owner rule 4 (best judgement, conservative and local-first). IDs
`SHOW-011-D1…` are cited from the plan, the contract and the code.

## SHOW-011-D1: Tempo from tap times

- **Decision**: the period is the slope of the least-squares line through the last (up to) 8
  accepted tap times against their index; tempo = 60 s / period. The anchor (beat phase) is the
  last accepted tap.
- **Rationale**: evenly spaced taps give their interval exactly; random timing errors average over
  every tap. With per-tap errors bounded by e, the slope error is at most e·Σ|wᵢ|/Σwᵢ² (wᵢ the
  centered indices): 0.8e at four taps (±16 ms for e = 20 ms, about ±4 BPM at 120) and 0.38e at
  eight (±7.6 ms, about ±1.9 BPM). Eight taps bound the memory and let a tempo change take over
  within eight taps.
- **Alternatives**: median of intervals (the brief's first suggestion): at four taps it is one
  interval, with the full ±2e error; mean of intervals equals (last − first)/(n − 1) and ignores
  the middle taps; exponential smoothing depends on tap order and needs a tuning constant.

## SHOW-011-D2: Limits and sequences

- **Decision**: 60-200 BPM (ANL-005's range). Interval < 300 ms: "too fast", the tap is ignored
  (a bounce cannot break a sequence). 1 s < interval ≤ 2 s: "too slow", the sequence restarts at
  that tap. Interval > 2 s: a pause, the sequence restarts at that tap without feedback. A tap at
  exactly the same time as the previous one is "too fast". A manual tempo stays while a new
  sequence builds and is replaced at that sequence's fourth tap.
- **Rationale**: two seconds is twice the slowest supported beat, long enough not to cut a slow
  performer and short enough that a deliberate re-tap starts fresh.
- **Alternatives**: a tolerance band around the limits (makes the reported range fuzzy);
  rejecting the whole sequence on one bad tap (punishes a single slip).

## SHOW-011-D3: The estimate in the app

- **Decision**: the analysis tap has one reader. While the circular spectrum is shown, its
  `LiveBandAnalyzer` pipeline is the reader, and the tempo subscribes to that pipeline through an
  additive hook (`subscribe`/`unsubscribe`). While projectM is shown, a `TempoAnalyzer` owned by
  the app's tempo coordinator runs its own ANL-016 pipeline on the tap. The coordinator switches
  in `resumeActiveVisual`/`pauseActiveVisual`, so the tempo analysis runs exactly when a visual
  runs; it is also a `PresentationBoundResource` (PERF-011) so a presentation loss stops it before
  the registry returns. Stopping clears the estimate (no stale "Detected").
- **Rationale**: no change to AudioCore (a second tap) or to who owns the circular spectrum's
  pipeline; the hook is six lines.
- **Alternatives**: one app-wide pipeline shared by every consumer (right long-term, but it moves
  VIS-001's ownership and is MOD-001/PERF-013 territory); no estimate while projectM is shown (the
  default visual would never show "Detected").

## SHOW-011-D4: Estimate mapping

- **Decision**: frames give the tempo and confidence (latest frame wins; `bpm == nil` means no
  estimate); beat events give the beat position: host time of the beat = event host time −
  (event session sample − beat sample) / sample rate. Session start and end clear the estimate. An
  estimate counts only with confidence ≥ 0.5. Without a beat event yet, the estimate has a tempo
  but no phase (`nextBeat` returns nil).
- **Rationale**: uses the bus exactly as ANL-016 documents (one clock for frames and events).

## SHOW-011-D5: Polling

- **Decision**: the coordinator polls the subscription every 250 ms on the main actor while
  analysis runs. The readout shows whole BPM, so 4 Hz is enough; beat-exact consumers (later rows)
  compute beats from the snapshot's anchor and period, not from the poll.
- **Alternatives**: a display-link poll (60 Hz for a number that changes rarely).

## SHOW-011-D6: Clock and UI test

- **Decision**: the model takes times as arguments. The app passes `MonotonicClock.nowNanoseconds()`
  (AudioCore; the bus's clock). DEBUG builds accept `-uitestTapInterval <ms>`: each tap advances a
  synthetic clock by that interval, so the UI test gets exact taps.
- **Rationale**: UI taps are not precisely timed; the hook is compiled out of Release.

## SHOW-011-D7: Persistence

- **Decision**: none (SHOW-011-R16). `TempoSnapshot` is `Codable` for later show files (SHOW rows),
  not written here.
