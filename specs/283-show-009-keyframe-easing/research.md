# Research: SHOW-009 Keyframe Easing

## SHOW-009-D1 Mode ownership, Stepped and Hold

- **Decision**: The left key's mode shapes the segment to the next key (SHOW-008 convention). Stepped = SHOW-008's
  former Hold (flat until the next key, jump there). Hold = a cut key: the arriving segment stays at the previous key's
  value (whatever that key's mode) and the leaving segment stays at the Hold key's value.
- **Rationale**: Keeps every SHOW-008 show's look (its `hold` is read as Stepped). Gives Hold a distinct, documented
  meaning that is useful on stage (a value that cuts in at a moment, like a cue) and keeps exact values at keys.
- **Alternatives**: Hold = Stepped (rejected: two names for one behavior); Hold ignoring its own value at its time
  (rejected: breaks the SHOW-008 exactness rule); stepped as CSS `steps(n)` (rejected: needs a step count, and the
  brief's reference value is 0.0 at the middle).

## SHOW-009-D2 Cubic curve

- **Decision**: Monotone piecewise cubic Hermite. Tangent at key j (in value per millisecond) is non-zero only when
  both segments around j are Cubic segments (key j−1 and key j are Cubic and neither arriving key is Hold) and the two
  secants Δ0, Δ1 have the same sign; then m = (w1 + w2) / (w1/Δ0 + w2/Δ1) with w1 = 2h1 + h0, w2 = h1 + 2h0
  (Fritsch–Butland weighted harmonic mean, as in PCHIP). Otherwise 0. Value on a segment of length h with
  u = (t − t0)/h: y = h00·y0 + h10·h·m0 + h01·y1 + h11·h·m1 (h00 = 2u³ − 3u² + 1, h10 = u³ − 2u² + u,
  h01 = −2u³ + 3u², h11 = u³ − u²), then clamped to [min(y0, y1), max(y0, y1)].
- **Rationale**: The weighted harmonic mean keeps |m| ≤ 3·min(|Δ0|, |Δ1|), which makes each segment monotone
  (Fritsch–Carlson condition), so a curve never overshoots its keys or the parameter range; zero tangents at run ends
  and extrema make the two-key case the standard ease-in-out 3u² − 2u³ (0.5 at the middle). The clamp only absorbs
  floating rounding.
- **Alternatives**: Cubic Bézier with fixed ease-in-out handles (rejected: identical to Ease for every segment, no
  flow through keys); Catmull–Rom (rejected: overshoots without extra clamping); PCHIP's three-point end slopes
  (rejected: ends would not ease, and could start abruptly).

## SHOW-009-D3 Exactness

- **Decision**: Unchanged from SHOW-008: at a key time the stored sample is returned before any curve runs; the
  fraction is computed from integer nanoseconds of one segment.

## SHOW-009-D4 Colours

- **Decision**: Cubic on a colour track uses the two-key shape (fraction 3u² − 2u³) mixed in linear light; Hold and
  Stepped hold the colour.
- **Rationale**: Per-channel multi-key tangents in linear light add code with no visible value for one-colour palettes.

## SHOW-009-D5 Storage

- **Decision**: `interpolation` keeps SHOW-008's names (`linear`, `hold` = Stepped, `ease`). New optional `easing`
  (`"hold"`, `"cubic"`) written only for Hold and Cubic; the `interpolation` beside it is the nearest older curve
  (Hold → `hold`, Cubic → `ease`). Read: a known `easing` wins; otherwise `interpolation`; missing → Linear; unknown
  `interpolation` with no known `easing` → keyframe dropped (counted, SHOW-008).
- **Rationale**: SHOW-008 builds drop keyframes with an unknown `interpolation`; this layout lets them read new shows
  with a close look instead. No version bump, and shows without the new modes keep their bytes.
- **Alternatives**: New names in `interpolation` (rejected: SHOW-008 builds would drop those keyframes).

## Shared code

- The existing smoothstep (`ShowKeyframeInterpolation.shaped`, SHOW-008) serves Ease and the two-key colour Cubic.
  No monotone cubic existed in ParameterGraph or Compositor; `MonotoneCubic` lives in ShowControl, its only user.
  MOD-016's smootherstep and MED-007's Ken Burns easings are different curves and stay where they are.
