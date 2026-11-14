# Research: MOD-009 Tempo-Synced LFO

## MOD-009-D1 Tempo source: consume SHOW-011's snapshot

- **Decision**: The oscillator takes a BPM or nil. The app passes `TempoSnapshot.lfoTempoBPM` (its `bpm`):
  manual tap tempo if set; else ANL-005's estimate with confidence ≥ 0.5 (`TapTempoRules.minimumEstimateConfidence`,
  ANL-005's "high") in 60…200 BPM; else nil → the stored rate.
- **Rationale**: `TempoSnapshot` is documented as the one read API for tempo consumers and already names
  MOD-009; re-implementing the order would let consumers disagree. ParameterGraph cannot import
  PerformanceControl (the dependency runs the other way), so the adaptor is a one-line extension in
  PerformanceControl and its test drives a real `TempoSource` into an `LFOBank`.
- **Alternatives**: a separate confidence floor for oscillators (rejected: two floors would make the readout
  say "stable" while the LFO ignored it); reading `TempoEstimate` directly (rejected: bypasses the manual
  override).

## MOD-009-D2 Continuous phase across rate changes: piecewise segments

- **Decision**: Per synced slot the bank stores a segment (start nanoseconds, start phase, rate). Each frame
  the slot's effective rate r = min(sync rate at the tempo, or the stored rate without tempo; cap) is
  compared with the segment's; if it differs, the phase reached at this frame under the old segment becomes
  the new segment's start phase. The phase is `frac(φ₀ + r·(t − t₀))` with MOD-007's exact split
  (whole seconds, remainder, fused multiply-add).
- **Rationale**: Continuous by construction; a constant rate never rebases, so MOD-007's no-drift proof holds;
  identical inputs (frame times and tempos) give identical outputs. Rebasing costs one phase evaluation.
- **Alternatives**: accumulate φ += r·Δt per frame (rejected: drifts and depends on frame rate); rebase the
  origin only (equivalent but loses the start phase); apply segments to free oscillators too (rejected:
  would change MOD-007's pure-function contract for Reduce flashing toggles; out of scope).
- **Frame bound**: across a change at frame time t the phase moves by r_old·(t − t_prev) + r_new·0 up to t,
  then r_new per second after; so a frame-to-frame step never exceeds max(r_old, r_new)·Δt cycles.

## MOD-009-D3 Lengths and BPM range

- **Decision**: beats per cycle ∈ {¼, ½, 1, 2, 4, 8}; BPM clamped to 40…240, non-finite or ≤ 0 → no tempo.
  Rate = BPM / 60 / beats: 0.083…16 Hz, inside MOD-007's 0.01…20 Hz. Reduce flashing caps at 3 Hz.
- **Rationale**: Exact binary fractions compare exactly after JSON; the range covers tap tempo and ANL-005
  (60…200) with margin. Dotted/triplet left out (spec Clarifications).

## MOD-009-D4 Scene field

- **Decision**: entry key `sync`: `{"beats": <number>}`; `rate` stays required (fallback, and what an older
  app uses). Issues: `invalidLFOSync` (sync not an object → path `.sync`; beats missing or not finite
  positive → `.sync.beats`), `unknownLFOSync` (finite positive but not allowed → `.sync.beats`). Both warnings;
  repair groups `invalidMappings` / `unknownContent`, no action; the oscillator stays live without sync.
  Unknown keys inside `sync` are kept (the whole entry is verbatim).
- **Alternatives**: a bare number `"sync": 1` (rejected: no room for later options such as alignment); making
  the oscillator unusable on a bad sync (rejected: a later version's length should still move).

## MOD-009-D5 App feed

- **Decision**: `NativeSpectrumHost.lfoTempoBPM: (@MainActor () -> Double?)?`, read once per frame in
  `applyModulation` only when the bank has a synced oscillator; `AppCoordinator+LFOs.swift` sets it to read
  `tempo.snapshot.lfoTempoBPM` (the coordinator updates the snapshot on taps and on its 250 ms poll).
- **Rationale**: one small closure, no new observation; frames see tempo changes within one poll.

## MOD-009-D6 Beat alignment: not included

- **Decision**: no alignment to `TempoSnapshot.anchorNanoseconds`; recorded in the spec Clarifications.
- **Rationale**: the anchor moves with every analysed beat and every tap; following it would jump the phase.
