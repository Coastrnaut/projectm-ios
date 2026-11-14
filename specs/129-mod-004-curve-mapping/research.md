# Research: MOD-004 Curve Mapping

## MOD-004-D1 — Formulas and why each is monotonic under rounding

- **Decision**: with x the clamped input (non-finite → 0, then limited to 0…1):
  - linear: x;
  - ease-in: `pow(x, p)`;
  - ease-out: `1 − pow(1 − x, p)`;
  - ease-in-out: `0.5·pow(2x, p)` for x < 0.5, else `1 − 0.5·pow(2(1 − x), p)`;
  - logarithmic: `log1p(k·x) / log1p(k)`;
  - exponential: `expm1(x·log1p(k)) / k` (the exact inverse of logarithmic);
  - piecewise: MOD-003's `LinearMapping.interpolate(from: y₀, to: y₁, at: (x − x₀)/(x₁ − x₀))` on
    the segment holding x, with implicit ends (0, 0) and (1, 1).

  Every result is then limited to 0…1 and the ends are pinned: input 0 → 0, input 1 → 1.
- **Rationale**: IEEE-754 rounding is monotonic (a ≤ b ⇒ round(a) ≤ round(b)), so subtraction from
  a constant, multiplication or division by a positive constant, and halving preserve order;
  `pow` (positive base, fixed exponent), `log1p` and `expm1` are monotonic in the platform libm.
  Limiting to 0…1 preserves order, and pinning the ends to the global minimum and maximum of the
  output range cannot create a decrease. The ease-in-out halves meet at 0.5 (left ≤ 0.5 ≤ right).
  Piecewise segments use MOD-003's bounded, monotonic interpolation and start exactly at their left
  point, which is the previous segment's upper bound. The acceptance tests check all this on a dense
  grid and on adjacent representable inputs (MOD-004-S1), so a libm that broke monotonicity would
  be caught.
- **Alternatives**: `log(1 + k·x)` (loses precision for small k·x; `log1p` is exact there);
  `(pow(1 + k, x) − 1)/k` (same, cancellation near 0).

## MOD-004-D2 — Piecewise interpolation

- **Decision**: linear segments, at most 8 interior points, x strictly increasing inside (0, 1),
  y in 0…1 non-decreasing.
- **Rationale**: exact monotonicity through MOD-003; easy validation; 8 points are enough for
  hand-drawn response shapes and keep the per-frame scan tiny.
- **Alternatives**: Fritsch–Carlson monotone cubic (smooth but extra rounding paths; can be added
  later as a new kind, stored data stays readable); 16 points (no use case).

## MOD-004-D3 — Invalid curves

- **Decision**: `validationProblem` names the first fault (exponent out of 1 < p ≤ 8 or not finite;
  strength out of 0 < k ≤ 1000 or not finite; more than 8 points; a non-finite coordinate; x not
  inside (0, 1); x not strictly increasing; y outside 0…1; y decreasing). Bindings refuse with
  `AudioFeatureBindingError.invalidCurve`. `apply` on an invalid curve limits the parameter into
  range (a NaN exponent or strength acts as linear) and skips points that would break the rules,
  considering at most the first 8 — so even invalid curves are bounded, monotonic, exact at the
  ends and allocation-free.
- **Alternatives**: repairing stored curves silently (rejected, Clarifications); a failable
  initializer (breaks plain enum construction and editing).

## MOD-004-D4 — Linear bit-identity

- **Decision**: `.linear.apply(s)` returns `LinearMapping.clampedPosition(s)`. The modulator's
  signal is already clamped to 0…1 (MOD-003 position, envelope between clamped values), and
  `interpolate` clamps again, so `interpolate(apply(s)) == interpolate(s)` bit for bit. A test
  compares both over a 10,001-point grid plus edge values, including −0.

## MOD-004-D5 — Scene storage

- **Decision**: binding field `"curve": {"kind": "<kind>", …}` with `exponent` (ease kinds),
  `strength` (logarithmic, exponential) or `points: [{"x":…, "y":…}, …]` (piecewise); omitted for
  linear (`{"kind":"linear"}` is still read). Unknown fields inside a readable curve are dropped
  with `droppedField`, as elsewhere. Anything unreadable (unknown kind, wrong types, missing
  parameter, not an object) is kept verbatim in the binding's unknown fields, and restore rejects
  the binding with `unsupportedCurve` (a warning; MOD-013 preserves rejected bindings verbatim, so a
  re-save writes it back). A readable but invalid curve rejects its binding with `invalidBinding`
  through the modulator's refusal. No new `SceneDecodeError` case, so QA-004's meta-test and error
  table are unchanged; no format version bump (optional field).

## MOD-004-D6 — Text form for MIDI-004

- **Decision**: `linear`, `easeIn:<p>`, `easeOut:<p>`, `easeInOut:<p>`, `log:<k>`, `exp:<k>`,
  `piecewise:<x>,<y>/<x>,<y>…` (`piecewise:` alone is the empty curve); numbers as Swift's
  `Double.description` (shortest round-trip). Reading is strict: an unknown tag, a bad number or
  wrong arity gives nil; reading does not validate ranges (the caller validates, as for scenes).
  MIDI-004 will append `;curve=<form>` to `cc:<ch>:<num>=<id>`; MIDI-003 already ignores options.

## MOD-004-D7 — No UI, no new SHD-009 opcode

- **Decision**: no curve picker (no user binding editor exists; recorded in Clarifications);
  `ExpressionMapping.curve` instead of an opcode.
