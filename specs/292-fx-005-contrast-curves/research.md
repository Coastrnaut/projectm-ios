# Research: FX-005 Contrast Curves

Audit (spec "Baseline"): no contrast curve exists; FX-003's gamma has no pivot and FX-002's tone map is identity in
range. Reused: FX-003's `ColorGrade`/`ColorGradeCoefficients` (flags, exact bypass, sanitising, typed steps), FX-002's
`ToneMap.map`/`cmp_tone_map`, the `cmp_grade` compile site, FX-020's `fx.grade` scene entry, FX-004's patterns for a
new grade control (setting key, catalog, section row, tests).

## FX-005-D1: Position — last, after the hue, on display-range values

- **Decision**: step 7 of the grade: `v ← ToneMap.map(v)` (FX-002's step, which is identity when every channel is
  ≤ 1), then the curve per channel. FX-002's tone map that follows in `cmp_display` is then identity bit for bit.
- **Rationale**: a curve is defined on 0…1; compressing HDR values with FX-002's luminance-keeping step first keeps
  highlight hue, and the curve applies exactly once also in FX-020's grade-before-Trails pass (no tone map there).
- **Alternatives**: before gain (curve on unbounded values; needs an HDR curve); after the tone map in `cmp_display`
  (lost when FX-020 grades before Trails); clamping to 1 first (clips HDR highlights' hue).

## FX-005-D2: Per channel

- **Decision**: the same monotone curve on r, g and b.
- **Rationale**: greys stay grey exactly; bounds per channel follow from the curve's; film convention.
- **Alternatives**: a luminance curve scaling rgb (keeps hue but can exceed 1 and needs another gamut step).

## FX-005-D3: S-curve

- **Decision**: pivot p = 0.18 (linear mid-grey), c = 1 + s: x ≤ p → p·(x/p)^c; x > p → 1 − (1 − p)·((1 − x)/(1 − p))^c.
- **Rationale**: monotone, C¹ at p (slope c from both sides), f(0) = 0, f(1) = 1, f(p) = p exactly in real
  arithmetic; one `pow` per channel.

## FX-005-D4: Filmic

- **Decision**: F(x) = S(T(x)), T(x) = x²(1 + τ)/(x + τ) (toe, slope 0 at black), S(y) = y(1 + σ)/(y + σ)
  (shoulder, slope σ/(1 + σ)·T′(1) at white), τ = 0.1, σ = 0.5; output x + s·(F(x) − x).
- **Rationale**: both factors are increasing on 0…1 with T(0) = S(0) = 0, T(1) = S(1) = 1 exactly; the blend is a
  convex combination, so monotone, and the `x + s·(F − x)` form keeps 0 and 1 exact in floating point. Distinct from
  the S-curve (mid-grey 0.18 → 0.30 at s = 1) and from FX-002's tone map (identity in range). FX-002 has no toe or
  shoulder to reuse; Hable's curve was rejected: on display-range input it lifts the shadows (slope ≈ 2 at black).

## FX-005-D5: Bounds and extremes

- **Decision**: the scalar curve clamps its input to 0…1 (NaN → 0) and its output to 0…1; the grade already sanitises
  NaN/±Inf/negatives to 0 (step 0) and FX-002's step maps large values into range.
- **Rationale**: the acceptance's "extreme values stay bounded" holds for the scalar function and the whole grade.

## FX-005-D6: Block and flags

- **Decision**: `CMPGrade` gains `float4 contrast` (c, s, τ, σ) after `pad1` (offset 64, size 80); flags 256 =
  S-curve, 512 = Filmic. Earlier offsets unchanged.
- **Rationale**: appending keeps FX-003/FX-004 offsets; FX-005's own bits leave 64 and 128 to parallel rows.

## FX-005-D7: Flash guard, grade pass

- **Decision**: no change: `CompositeFlashGuard` and `OutputGradePass` already call `cmp_display`/`cmp_grade` with the
  same block.

## FX-005-D8: Scene and settings

- **Decision**: `fx.grade` parameters `contrast` (string) and `contrastStrength` (number), read with the existing
  rules plus: a missing name → linear; a non-string or unknown name → linear with a `valueClamped` warning; kept as
  written. Settings: String key (unknown → linear) and Double key (absent, NaN or non-number → 0.5, clamped).
- **Rationale**: optional fields, no version bump; old scenes read as Linear (the field is absent).

## FX-005-D9: UI

- **Decision**: a segmented-style `Picker` "Contrast" (`colorContrastPicker`) and an `.accessibleParameter` slider
  "Contrast strength" (`colorContrastStrengthSlider`, percent, 0.05 per swipe) shown only while a curve is chosen.

## FX-005-D10: ADR

- **Decision**: amend ADR-0050 (the output colour grade) with the operator, block growth and flag bits; no new ADR.
