# Research: ANL-013 Stereo Correlation

## ANL-013-D1 Where to measure

**Decision**: inside the ANL-016 pipeline's `pump`, on each interleaved chunk before `SpectrumStream.append` mixes it to mono.
**Rationale**: the tap has exactly one consumer (the pipeline); its chunks are already post AUD-009/AUD-008; the pipeline already owns the session clock and resets.
**Alternatives**: `WaveformTap.stereoOutput` (VIS-004's history: a display buffer, overwritten, not every sample); a second tap reader (breaks the one-consumer rule).

## ANL-013-D2 Measure and smoothing

**Decision**: Pearson-style correlation without mean removal (the audio is AC), sums per 1,024-frame block in Double, exponential smoothing of the three sums and the sample weight with a = exp(−B/(τ·rate)), τ = 0.1 s; r = S_LR/√(S_LL·S_RR) clamped to −1…1.
**Rationale**: the classic phase-meter definition; smoothing sums is energy-weighted and exact for ±1 cases; block updates on the sample clock make the result chunking-invariant and deterministic.
**Alternatives**: smoothing r itself (quiet passages weigh as much as loud ones; transitions through silence pull to 0); per-hop blocks of 512 (no benefit; the frame carries the latest value anyway).

## ANL-013-D3 Floor

**Decision**: per-channel smoothed mean square ≤ 0.5·10⁻⁷ (−70 dB re a full-scale sine) → r = 0, no signal.
**Rationale**: matches ANL-011/012's −70 dB rule; a one-sided signal has no defined correlation and must not read ±1.

## ANL-013-D4 Warning hysteresis

**Decision**: raise below −0.5 for 44 consecutive blocks (1.02 s); clear above −0.3 for 44 blocks; in between both counters restart. Counted in blocks, so tests need no clock.
**Alternatives**: a single threshold (flickers around −0.5); clearing on the first block above −0.5 (flickers on music with brief anti-phase content).

## ANL-013-D5 Status and announcement

**Decision**: source status suffix " · Stereo channels look phase-inverted"; overlay line `stereo: r -0.98 phase-inverted`; ACC-011 rows X3a (raise, system, persistent text in the indicator) and X3b ("Stereo phase normal", system, caption) on the `source` lane; raise announcements at most once per 30 s, X3b only after an announced X3a.
**Rationale**: text, not colour; one lane with the source state the warning is about; the 30 s throttle stops a borderline feed from talking every two seconds.

## ANL-013-D6 Binding value

**Decision**: `audio.correlation` = (r + 1)/2 in 0…1, opcode 34; raw r in `AudioFeatureFrame.correlation`.
**Rationale**: MOD-002 sources are 0…1; 0.5 is "unrelated or silent", which keeps a bound parameter mid-range in silence.
