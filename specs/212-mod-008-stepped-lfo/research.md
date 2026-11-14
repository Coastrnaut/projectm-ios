# Research: MOD-008 Stepped LFO

## MOD-008-D1: Counter-based levels

- **Decision**: level(seed, n) = top 53 bits of mix(mix(seed) &+ UInt64(bitPattern: n)) / 2⁵³, where mix is
  SplitMix64's finalizer (add 0x9E3779B97F4A7C15, then the two xor-shift-multiply rounds). The seed is
  pre-mixed so nearby seeds (0, 1, 2…) give unrelated sequences rather than shifted copies.
- **Rationale**: the acceptance ("same seed and timebase yield identical step values") holds by
  construction: a level is a pure function of (seed, step); no stream state can drift with frame chunking,
  dropped frames or app restarts. Integer-only, allocation-free, identical on every platform (no
  floating-point in the hash; the final conversion is exact).
- **Alternatives**: a stateful PRNG advanced once per step (breaks when frames skip steps, needs history);
  Foundation/`SystemRandomNumberGenerator` (not seedable); `drand48` (global state, not on every platform
  identically).

## MOD-008-D2: Default seed

- **Decision**: stored `seed` is `UInt32` (0…4294967295, exact in a JSON double); without it the seed is
  `2³² + position` (outside the stored range, so never equal to a stored seed).
- **Rationale**: two unseeded sample-and-hold oscillators in one scene must not move in lockstep, and a scene
  must replay identically. Wall-clock or random defaults would break replay.
- **Alternatives**: a random seed written at creation (no editor creates oscillators); 64-bit seeds (lose
  precision in JSON parsers above 2⁵³).

## MOD-008-D3: Exact step number

- **Decision**: the existing exact phase computation (whole seconds × rate with a fused multiply-add error
  term) also yields the whole-cycle count: ⌊rate·s⌋ (exact) plus ⌊fraction sum⌋. Phase and step come from the
  same sum, so a frame at a boundary is consistently in the new step with phase 0.
- **Rationale**: stays exact for hours (Int64 cycles); no separate floor of a large double.

## MOD-008-D4: Synced step continuity

- **Decision**: MOD-009's `LFOPhaseSegment` gains `startCycle: Int64`; a new segment starts at the step and
  phase reached under the old one.
- **Rationale**: a tempo change must not restart or repeat the sequence (MOD-008-R8).

## MOD-008-D5: Scene fields

- **Decision**: `duty` (square only, always written for square), `seed` (when set), `glide` (sample-and-hold,
  when not 0). Read for every shape with defaults; out of range → `invalidLFO` at `$.lfos[i]`; a non-integer
  or out-of-range `seed` → `invalidLFO` at `$.lfos[i].seed`. No new issue codes, no version bump; older apps
  report the new shapes as `unknownLFO` and keep the entry (MOD-007 L6).
- **Rationale**: sine/triangle scenes encode byte-identically (QA-004 matrix unchanged).

## MOD-008-D6: Glide

- **Decision**: during phase < glide the level is prev + (cur − prev) · phase / glide; prev = level(seed, n − 1)
  (pure). Glide 0 is a hard step. Square has no glide (its edges are its point; Reduce flashing bounds them).
