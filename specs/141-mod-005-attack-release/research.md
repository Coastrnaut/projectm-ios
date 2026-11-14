# Research: MOD-005 Attack/Release Envelope

## MOD-005-D1: The envelope shape and its definition

- **Decision**: Keep MOD-002's one-pole exponential smoother. Per advance, with elapsed Δt and the
  direction's time constant τ: `s ← s + (x − s)·(1 − exp(−Δt/τ))`. After a step from s₀ to x the
  signal is `x + (s₀ − x)·exp(−t/τ)`: 63.2 % of the distance at τ, 86.5 % at 2τ, 95 % at 3τ. The
  10–90 % rise time is τ·ln 9 ≈ 2.197 τ; helpers convert both ways.
- **Rationale**: Exponential composition is exact for any sequence of Δt
  (∏ exp(−Δtᵢ/τ) = exp(−Σ Δtᵢ/τ)), so the response depends only on elapsed time, never on frame
  rate or jitter (up to rounding). It is MOD-002's stored meaning, so scenes keep their behaviour.
- **Alternatives**: linear slew (rate in units/s; corners, and a different meaning for stored
  values); a two-pole or critically damped filter (overshoot or more state, no benefit for
  modulation); storing 10–90 % rise times (needs migration of every scene).

## MOD-005-D2: Direction rule

- **Decision**: attack when the target is above the current signal, release when below; equal means
  no movement (both formulas give the same result). τ = 0 in the chosen direction snaps to the
  target on that advance, even with Δt = 0 (MOD-002 behaviour: instant means instant).
- **Rationale**: Unchanged from MOD-002; the direction is re-decided each frame, so a rise
  interrupted by a fall immediately uses release.

## MOD-005-D3: Robustness

- **Decision**: In the pure step: Δt that is ≤ 0 or non-finite applies no smoothing; a non-finite
  previous signal is replaced by the target; a non-finite target is treated as 0 (MOD-003's rule,
  already applied by `position(of:)`); the result is clamped to 0…1. The modulator keeps the clock
  rules: Δt from the injected nanosecond time, 0 on the first advance or when time does not
  increase, capped at 0.25 s per advance.
- **Rationale**: For valid inputs (s, x in 0…1, finite Δt > 0, τ in 0…60) the formula is a convex
  combination and needs none of this; the guards only matter for values that should never occur,
  so bit-identity holds and no input can produce NaN.

## MOD-005-D4: Live change of times

- **Decision**: `AudioFeatureModulator.setEnvelope(_:for:) throws(AudioFeatureBindingError)`:
  refuses an unbound target (`unknownTarget`) and invalid times (`invalidEnvelope`) without change;
  otherwise replaces the binding's envelope in its slot, keeping signal and last time.
- **Rationale**: Rebinding restarts at 0 by MOD-002's contract; an editor needs continuity. No
  allocation (the slot is updated in place).

## MOD-005-D5: Scene reporting

- **Decision**: When `bind` throws `invalidEnvelope` during restore, the issue path is
  `$.bindings[i].envelope` (code `invalidBinding`, outcome rejected, binding preserved). Other
  errors keep the binding path.
- **Rationale**: SCN-012's report then points at the faulty field; no new code means no repair
  grouping or QA-004 change.

## MOD-005-D6: Tolerance and test design

- **Decision**: Compare each frame to the analytic curve within 0.01 absolute (actual errors are
  rounding-level, ~1e-15); the 63.2 % crossing frame must lie within one frame duration of τ; three
  attack/release pairs ((0.05, 0.5), (0.25, 0.1), (1, 2)) × three frame patterns (60 fps, 120 fps,
  seeded jitter 4–40 ms) — nine short simulations, each a few hundred advances.
- **Rationale**: The roadmap asks "within tolerance"; 1 % absolute is the brief's example and is
  easily distinguishable from a frame-count-based smoother (which would be off by 2× between 60 and
  120 fps).

## MOD-005-D7: Scope exclusions

- MIDI CC smoothing (MIDI-003/004): out of scope, MIDI files untouched.
- ANL-003 spectrum smoothing: separate type (`BandSmoother`), unchanged.
- User-facing controls: none (no binding editor exists).
