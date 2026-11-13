# Research: MOD-003 Linear Mapping

All questions were resolved in the spec's Clarifications; this file records the evidence.

## MOD-003-D1: Interpolation formula

- **Decision**: the precise two-branch interpolation of C++20 `std::lerp` (WG21 paper P0811), for
  positions t in 0…1 and ends a (start), b (end):
  - if a ≤ 0 ≤ b or b ≤ 0 ≤ a: `t·b + (1 − t)·a`;
  - else if t = 1: `b`;
  - else `x = a + t·(b − a)`, then `min(b, x)` when b > a, otherwise `max(b, x)`.
- **Rationale**: exact at t = 0 (`a + 0·(b − a) = a`; `0·b + 1·a = a`) and t = 1, bounded by the
  ends, monotonic in t, and overflow-free (the opposite-sign branch never subtracts; same-sign
  differences are no larger than the larger end). The opposite-sign branch is MOD-002's formula
  with the sum's operands swapped, and IEEE addition is commutative, so it is bit-identical.
- **Audit evidence (2026-11-13, Python doubles, same IEEE 754 binary64 arithmetic as Swift)**:
  - MOD-002's `(1 − s)·a + s·b` over 100,001 evenly spaced s: exact at both ends for all 11 ranges
    tried, but the constant range 0.1…0.1 left the range at 4,725 positions and reversed at 4,579.
  - Over 20,000 random end pairs (magnitudes 1e−8…1e8, 30 % equal or opposite), walking 50
    adjacent representable s each: MOD-002's formula clamped to the ends had 20,763 reversals in
    1,000,000 steps; the two-branch formula had 0 reversals and 0 out-of-range results, and agreed
    bit for bit with MOD-002 in 80.6 % of samples (all opposite-sign cases included).
  - Difference from MOD-002 for same-sign ranges over 1,001 evenly spaced positions, in units in
    the last place of the larger end: 0.2…0.9 at most 2.0; 0.9…0.1, −5…−1, 1e300…1.5e300,
    1e−9…2e−9, 0.1…0.1, 7…3 at most 1.0; 0.5…1 at most 0.5. Hence the 2-ulp bound in MOD-003-R7.
- **Alternatives**: MOD-002's formula unchanged (unbounded for constant ranges, not monotonic);
  plus a clamp (bounded, still not monotonic); `a + t·(b − a)` alone (not exact at t = 1).

## MOD-003-D2: One type, Double only

- **Decision**: a non-generic `LinearMapping` over `Double`, with a static
  `interpolate(from:to:at:)` for callers that have no input range (curves will shape the position
  and then interpolate).
- **Rationale**: the modulator works in Double; Float band levels widen exactly. A generic version
  costs specialization concerns in Debug builds with no current consumer.
- **Alternatives**: `LinearMapping<Value: BinaryFloatingPoint>` (deferred until a Float consumer).

## MOD-003-D3: Keep the binding's stored fields

- **Decision**: `AudioFeatureBinding` keeps `inputMinimum`, `inputMaximum`, `outputStart`,
  `outputEnd` and gains a computed `mapping` (get and set).
- **Rationale**: no source change for the app, tests or validation; the binding's `Hashable`
  identity is unchanged.
- **Alternatives**: replace the four fields with a stored `mapping` (API churn for no behavior).

## MOD-003-D4: Clamping and non-finite values

- **Decision**: positions are always clamped to 0…1; a non-finite position (NaN, from a NaN input
  or a degenerate range) reads 0; interpolation clamps its argument the same way. No extrapolation.
- **Rationale**: identical to MOD-002's `min(max(p.isFinite ? p : 0, 0), 1)`, and the roadmap asks
  for a bounded destination.
