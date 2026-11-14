# Research: ANL-015 Section Energy Change

## ANL-015-D1 Input

**Decision**: ANL-014's per-frame unsmoothed K-weighted level (`LoudnessReading.decibels`) inside the pipeline's `process`, clamped below to a −70 dB floor (non-finite → floor).
**Rationale**: reuses the existing weighted level (no second meter, no extra FFT); per-frame input on the hop clock makes results chunking-invariant; the floor makes silence a steady level.
**Alternatives**: AudioCore's `LevelMeter` (raw sink, unweighted, capture side); ANL-014's smoothed envelope (100/400 ms asymmetric and normalized/clamped at −60 dB, losing the low range).

## ANL-015-D2 Slow level

**Decision**: dB of the mean power of the last 35 frames (≈ 0.41 s), recomputed from a 35-entry ring each frame (no running-sum drift).
**Rationale**: BS.1770's momentary span; rectangular, so rises are seen within one or two frames and bursts are forgotten 0.41 s after they end. Recomputing the sum keeps it bit-deterministic.
**Alternatives**: one-pole in dB (delays the rise; event would land well after "one block after the dwell"); one-pole in power (slow release: a 1 s burst would read loud for 3-4 s and fire).

## ANL-015-D3 Reference

**Decision**: settle 2.0 s per session (R = slow level, no changes), then a one-pole follower τ = 8 s while idle or refractory, frozen while pending, set to the slow level on a fire.
**Rationale**: a section's level is the comparison point; the follower absorbs slow fades; freezing keeps the dwell's comparison stable.
**Alternatives**: a second, longer rectangular mean (8 s ring: 690 entries; the pending comparison would drift during the dwell).

## ANL-015-D4 State machine

**Decision**: idle → pending at |S − R| ≥ 6 dB (direction = sign); pending → idle when (S − R)·sign ≤ 3 dB; pending → fire when `frameEnd − startFrameEnd ≥ dwell` (88,200 samples); after a fire, refractory for 176,400 samples (no new pending).
**Rationale**: hysteresis bands plus a sample-counted dwell; the refractory and the reference snap make one transition fire once.

## ANL-015-D5 Exposure

**Decision**: bus event `.sectionChange(direction:levelDecibels:referenceDecibels:)` with `eventSample` = start frame end; frame fields `sectionChangeEnvelope` (τ 1.0 s, snap to 0 below 0.001) and `sectionLevelDecibels`; MOD-002 `audio.sectionChange`, opcode 35, inspector "Section change". No status event.
**Rationale**: the event serves bus subscribers (e.g. a future cue trigger), the envelope serves bindings like ANL-007's kick. Opcode 35: 34 = correlation; no branch uses 35.
