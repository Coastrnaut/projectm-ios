# Research: MOD-016 Random walk modulator

## MOD-016-D1: A pure function of seed and time, inside the oscillator bank

- **Decision**: a new oscillator shape `randomWalk`. Cycle n has the target T(n) = `SteppedRandom.level(seed, n)`
  (MOD-008-D1); at phase φ of cycle n the walk is W = T(n) + (T(n + 1) − T(n)) · e(φ). Output =
  clamp(center + amplitude · (W − 0.5), 0, 1). Step and phase come from `LFO.cycle(…)` (MOD-008-D3): exact
  integer cycle count and the exact phase, no accumulated state.
- **Rationale**: the acceptance ("seeded timeline reproduces identical values") holds by construction for
  every chunking and seek; the rate, phase, depth, centre, seed, tempo sync (MOD-009) and Reduce flashing cap
  are reused unchanged; bindings already read `audio.lfo.<i>`.
- **Alternatives**: a per-frame random increment or an Ornstein-Uhlenbeck process integrated per frame
  (depends on frame chunking, drifts, needs history); a separate modulator type outside the bank (duplicates
  the timing, seed, sync and scene code); gradient (Perlin) noise (needs a scale to stay in range: its
  bound is not by construction).

## MOD-016-D2: The ease between targets

- **Decision**: e(φ) = (1 − s)·φ + s·(6φ⁵ − 15φ⁴ + 10φ³), smoothness s in 0…1, default 1. Computed in Horner
  form: φ³·(φ·(6φ − 15) + 10).
- **Rationale**: both terms are monotone non-decreasing on 0…1 with e(0) = 0 and e(1) = 1, so W lies between
  T(n) and T(n + 1): no overshoot, the bound needs no clamp. s = 1 has zero first and second derivatives at
  each target (C²: eases in and out); s = 0 is a constant speed. A float check: e is evaluated for φ in
  0…<1; the result is clamped to 0…1 to guard rounding (a no-op for exact maths).
- **Alternatives**: cubic smoothstep (C¹ only); Catmull-Rom or Hermite splines through neighbouring targets
  (smoother tangents but overshoot, so values could leave the range); cosine interpolation (equivalent shape,
  needs `cos`, slope π/2).

## MOD-016-D3: Continuity bound

- **Decision**: the slope of e is at most m(s) = (1 − s) + s·15/8 (the blend's maximum is at most the sum of
  the parts' maxima, 1 and 15/8). With |T(n + 1) − T(n)| < 1, between two samples Δt apart at a constant
  rate r: |Δvalue| ≤ amplitude · m(s) · r · Δt. Tests assert this (with 1e-12 slack) for every frame.
- **Rationale**: a testable "no jumps" rule; across a cycle boundary W is continuous (both sides equal T(n)).

## MOD-016-D4: Scene field

- **Decision**: optional `smoothness` (number 0…1), written for `randomWalk` only when not 1; read for every
  shape with default 1; invalid → `invalidLFO` at `$.lfos[i]` (MOD-007 path). `seed` is reused (MOD-008-D2,
  also written when set). No new issue codes, no version bump; older apps report `randomWalk` as
  `unknownLFO` and keep the entry verbatim (MOD-007 L6).
- **Rationale**: scenes without random walks encode byte-identically (QA-004 matrix unchanged).

## MOD-016-D5: Independent targets

- **Decision**: targets are independent and uniform; "walk" means continuous motion from target to target.
- **Rationale**: correlated targets need history (breaks purity) or windowed averaging (shrinks the range);
  rate and depth already control how far it wanders per second.
