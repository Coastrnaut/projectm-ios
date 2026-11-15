# Research: FX-013 Posterization

Audit (spec "Baseline"): no posterization exists. Reused: FX-003's `ColorGrade`/`ColorGradeCoefficients` (flags,
exact bypass, sanitising, typed steps), FX-002's `ToneMap.map`/`cmp_tone_map`, FX-005's pattern for a new last grade
step (display-range first, appended block field, own flag bits, scene fields written only when active, setting keys,
catalog, section rows, tests), `LayerBlend.encode`/`decode` (the exact sRGB curve, CPU), `OutputPassRig` (GPU tests).

## FX-013-D1: Position — last, after FX-005's curve, on display-range values

- **Decision**: step 8 of the grade: `v ← ToneMap.map(v)` (identity when every channel ≤ 1), then quantise. FX-002's
  tone map that follows in `cmp_display` returns in-range values unchanged, so the quantiser is the last
  value-changing step; only the flash gain (one scalar per frame) and OUT-009's calibration (a fixed per-value map)
  follow, and both keep "at most L values per channel".
- **Rationale**: the acceptance needs at most L levels in the output; any later non-identity step would break it.
  Also applies exactly once in FX-020's grade-before-Trails pass (Trails then blend frames: documented).
- **Alternatives**: before the curve (the curve would bend the levels apart, still L values but uneven); after the
  tone map in `cmp_display` only (lost in FX-020's grade pass).

## FX-013-D2: Quantisation space — sRGB-encoded

- **Decision**: e = encode(clamp(x, 0, 1)) (exact sRGB curve), levels k/n of e, output decode(k/n).
- **Rationale**: matches the 8-bit screen: the sRGB target re-encodes decode(k/n) to one byte value per level, so
  "distinct values per channel" counts levels directly; perceptually even bands (linear levels crowd the highlights
  and crush shadows into one band at L = 2…6).
- **Alternatives**: linear light (uneven-looking bands).

## FX-013-D3: Rounding — nearest level, half up

- **Decision**: k = clamp(⌊e·n + t⌋, 0, n), t = 0.5 without dithering.
- **Rationale**: one formula for both modes; 0 → level 0 and 1 → level n exactly; the clamp bounds any input.

## FX-013-D4: Dither — ordered Bayer 4 × 4

- **Decision**: t = (B[y mod 4][x mod 4] + 0.5)/16 with B = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9],
  [15, 7, 13, 5]], (x, y) the output pixel.
- **Rationale**: deterministic, no texture or time dependence (no temporal shimmer, which would also be a flicker
  risk), each threshold in (0, 1) so k stays in the two levels around e·n; a flat value's mean over a 4 × 4 tile is
  within 1/32 of a level of the input.
- **Alternatives**: 8 × 8 Bayer (finer, 64 constants; not needed at L ≥ 2 on phone pixel density), blue noise (needs
  a texture), error diffusion (sequential, not a per-pixel operator).

## FX-013-D5: Block field and flags

- **Decision**: `float4 poster` = (n, 1/n, 0, 0) appended after FX-005's `contrast` (offset 80, block 96 bytes);
  flag 64 = posterize, 128 = dither (set only with 64). Bits 64 and 128 were free (FX-003/004 use 1-32, FX-005
  256/512).
- **Rationale**: earlier offsets unchanged; parallel FX rows append after.

## FX-013-D6: Pixel position in the grade

- **Decision**: `cmp_grade_at(float4 c, constant CMPGrade &g, uint2 p)` holds the grade; `cmp_grade(c, g)` =
  `cmp_grade_at(c, g, uint2(0))`; `cmp_display_at` likewise. `cmp_output`, `cmp_output_calibrated` and
  `cmp_grade_pass` pass `uint2(in.position.xy)`; the flash guard passes the pixel it samples, so it measures the
  dithered colour actually shown there.
- **Rationale**: dithering depends on position; keeping the old functions avoids breaking parallel callers.
- **CPU**: `ColorGradeCoefficients.apply(_:x:y:)`; `apply(_:)` = position (0, 0).

## FX-013-D7: Own sRGB helpers in the grade source

- **Decision**: `cmp_pz_encode` / `cmp_pz_decode` in the posterize source (same formulas as `cmp_encode` /
  `cmp_decode` and `LayerBlend`).
- **Rationale**: the flash guard compiles `displaySource` without `CompositorShaders.source`, where `cmp_encode`
  lives.

## FX-013-D8: Scene fields

- **Decision**: `fx.grade` may carry `posterize` (bool), `posterizeLevels` (number, rounded and clamped to 2…32,
  missing → 6) and `posterizeDither` (bool). Missing → off/6/off; a non-bool → default with a `valueClamped` warning.
  Written only while posterize is on or when the stored entry already had any of them.
- **Rationale**: FX-005's rule: other scenes stay byte-identical; old scenes read as off.

## FX-013-D9: Controls

- **Decision**: Settings → Color: "Posterize" toggle (`colorPosterizeToggle`); while on, "Posterize levels" slider
  (`colorPosterizeLevelsSlider`, 2…32, step 1, readout "6 levels", spoken "6") and "Dither" toggle
  (`colorPosterizeDitherToggle`). MOD-001 `effect.colorGrade.posterize` (boolean), `.posterizeLevels` (integer
  2…32 default 6), `.posterizeDither` (boolean), all `discreteManual`.
- **Rationale**: matches FX-005's picker-then-detail layout and ACC-005's slider helper (`.number(decimals: 0)`).

## FX-013-D10: ADR

- **Decision**: amend ADR-0050 (output colour grade) with step 8, the 96-byte block and flags 64/128, as FX-005 did.
