# Research: QA-003 Visual Diff Tolerances

## D1 — Where the comparator lives

- **Decision**: `ImageDiff` in `Packages/RenderGoldens/Sources/GoldenImages`.
- **Rationale**: the target already owns `GoldenImage` (RGBA8), is Foundation-only and runs on Linux in
  CI; QA-002 left its comparison "a value so the swap is local". The only callers are in this package.
- **Alternatives**: a new `ImageDiff` package (duplicates the image type or makes RenderGoldens depend
  on it for no gain); a test-only helper (not reusable by other packages' tests).

## D2 — Colour rule

- **Decision**: a pixel exceeds when max(|ΔR|, |ΔG|, |ΔB|, |ΔA|) > `channelTolerance` (0-255). Allowed
  exceeding (non-forgiven) pixels = min(⌊fraction × total⌋, `maxExceedingPixels` when set).
- **Rationale**: identical to QA-002 (so `.qa002` keeps every QA-002 test), simple to explain.
- **Alternatives**: perceptual ΔE (needs colour-space maths, no gain for regression detection); mean
  error (hides a localized regression).

## D3 — Geometry rule

- **Decision**: (a) neighbourhood forgiveness with Chebyshev radius r, bidirectional, match = colour
  tolerance; (b) 8-connected clusters of unmatched pixels, largest ≤ `maxClusterPixels`.
- **Rationale**: (a) tolerates a one-pixel rasterization shift of an edge without loosening the colour
  rule; bidirectional so a missing thin feature is not forgiven merely because background is nearby in
  one direction. (b) separates scattered noise (clusters of 1-2) from shape changes (one large blob),
  which a pure count cannot: 49 pixels in one blob and 49 scattered pixels have the same count. Integer
  maths only, deterministic, O(pixels × (2r+1)²) on exceeding pixels only.
- **Alternatives**: morphological opening of the mask (kills thin-line regressions, which then pass);
  edge-map IoU (sensitive to noise creating edges; more thresholds); SSIM as the gate (D4).

## D4 — Structural measure

- **Decision**: mean SSIM of luma (Rec. 709 weights, values 0-255, C1 = (0.01·255)², C2 = (0.03·255)²)
  over 8 × 8 windows at stride 4; reported always (nil below 8 × 8); a gate only when `minimumSSIM` is
  set; no preset sets it.
- **Rationale**: a single white pixel on black gives that window SSIM ≈ 0.05, so salt-and-pepper noise
  would fail an SSIM gate; the cluster rule is the geometry gate, SSIM is a reviewer's figure and an
  opt-in for callers with smooth content.

## D5 — Presets

| Preset | Colour | Fraction | Count cap | Radius | Cluster | SSIM |
|---|---|---|---|---|---|---|
| `exact` | 0 | 0 | 0 | 0 | — | — |
| `qa002` | 2 | 0.001 | — | 0 | — | — |
| `golden` (default) | 2 | 0.001 | — | 1 | 8 | — |

- `golden` vs. today's CI: the last green run's only non-identical capture differs by 1/255 on 4 pixels,
  inside the colour tolerance, so no exceeding pixel exists and neither new rule can fail it.
- Exact match where determinism is guaranteed: equal pixel hashes remain "identical"; run-to-run
  determinism asserts keep comparing hashes.

## D6 — Report and diff image

- **Decision**: `ImageDiffReport` with the figures of QA-003-R7; summary one line, failed rules named
  (`colour-count`, `cluster`, `ssim`, `size`). Bounding box over unmatched pixels, else over exceeding
  pixels, else nil. Diff image: QA-002's colours plus orange (255, 140, 0) for forgiven pixels and a cyan
  (0, 255, 255) 1-pixel outline of the bounding box drawn over unchanged pixels only.
- **Rationale**: reviewers see at once where the regression is and whether shifts were forgiven.

## D7 — Acceptance fixtures

- **Decision**: 128 × 96 fixture: horizontal gradient background, a filled 24 × 18 rectangle and a filled
  circle of radius 12. Noise: seeded salt-and-pepper pixels (set to black or white; each is unmatched,
  a cluster of 1 unless two land adjacent) within the allowed count, plus a seeded ±2 on every channel of
  every pixel (inside the colour tolerance). Regressions: rectangle moved 12 px right, circle scaled 1.5×,
  rectangle removed.
- Salt-and-pepper count: 10 pixels at 128 × 96 (12 allowed by the fraction) and 40 at 256 × 192 (49
  allowed); the generator keeps noise pixels at least 2 apart so the cluster figure is deterministic and
  1. A whole-image one-pixel shift must pass with radius 1. Determinism: same seed → same report.
