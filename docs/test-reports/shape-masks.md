# Test report: CMP-007 Shape masks

Feature: `specs/104-cmp-007-shape-masks` (branch `feature/cmp-007`). Host: the Mac Studio (build
machine of record), Xcode 27.2, Swift 6.4.2. Simulator results are not device evidence; no device
run was made.

## Baseline (CMP-007-T01, before any change, commit `892b3392`)

`swift test --package-path Packages/Compositor`: 255 tests, 2 skipped (benches), 0 failures, 9.6 s.
`swift test --package-path Packages/SceneFormat`: 93 tests, 0 failures, 2.8 s.

## CPU reference (`LayerMaskReferenceTests`, 10 tests, 0.003 s; host and Linux shape)

Circle distance and coverage at known pixels (exactly 1 at d = −band/2, exactly 0 at d = +band/2,
0.5 on the edge); a circle with equal scales stays round on 160 × 90 and 90 × 160 pictures (1e-9);
ellipse sign exact on both axes; rounded rectangle edges and the rounded corner ((√2 − 1)·r outside
the box corner), radius limited to half the shorter side; convex triangle; concave L with the notch
25 px outside, the same for reversed winding; a self-intersecting star has an even-odd hole; invert
is 1 − coverage and exactly 0 deep inside; a feather of 0.1 gives an 11 px band, monotonic, exactly 1
and 0 at its ends; the mask transform moves, scales and rotates clockwise; a far, tiny mask covers
nothing (inverted: everything); clamping of centre, scale, rotation −0, feather, points, corner
radius; refusals for 2 points, 33 points, collinear points and a non-finite point.

## GPU read-back (`LayerMaskCompositeTests`, 6 GPU tests + 1 opt-in bench, 0.8 s)

A solid opaque layer (linear premultiplied 0.8, 0.4, 0.2, 1) over transparent in a 96 × 64
`rgba16Float` output, masked and unmasked. Each pixel is classed with the CPU reference at its layer
pixel: outside (distance ≥ band/2 + 0.05 px; inverted mirrored) must be exactly (0, 0, 0, 0); inside
must be bit-equal to the unmasked render; edge alpha is compared with coverage × unmasked alpha.

| Shape | Outside pixels | Outside alpha ≠ 0 | Inside pixels | Inside ≠ unmasked | Edge pixels | Edge max error |
|---|---|---|---|---|---|---|
| circle (scale 0.6) | 4920 | 0 | 1092 | 0 | 132 | 0.0005 |
| rounded rectangle (r 0.25, rotated 0.3) | 3660 | 0 | 2278 | 0 | 206 | 0.0005 |
| convex polygon (hexagon, off-centre) | 4341 | 0 | 1613 | 0 | 190 | 0.0005 |
| concave polygon (L, rotated −0.2) | 4061 | 0 | 1851 | 0 | 232 | 0.0005 |
| inverted circle | 1092 | 0 | 4920 | 0 | 132 | 0.0004 |
| feathered ellipse (feather 0.1) | 3068 | 0 | 1664 | 0 | 1412 | 0.0005 |

Composition, each with 0 outside and 0 inside violations and edge error ≤ 0.01:

- CMP-005 transform (move 0.2, −0.1, scale 0.8, rotation 0.4) with the concave polygon: the reference
  evaluated at the inverse-mapped layer pixel matches; the untransformed reference does not (the mask
  moved with the layer).
- CMP-006 fit: a 30 × 60 portrait photo in `fit` with a 1.2 × 0.8 ellipse: fit bars stay transparent,
  the content above the ellipse is cut, the mask is centred on the layer rectangle.
- CMP-004 `screen`: alone (outside exactly transparent; `blendDraws` 1, `maskedDraws` 0: masked inside
  `cmp_blend`), and over an opaque backdrop (outside bit-equal to the backdrop alone; inside bit-equal
  to the unmasked screen result).
- CMP-003 opacity 0.5 × a feathered ellipse.
- A mask change at apply: shown from the next frame; no layer created, no picture allocated, no
  prepare; removing the mask returns the bit-identical unmasked render with `maskedDraws` 0.
- Normal masked layers: `maskedDraws` 1 and `blendDraws` 0 (no extra pass; CMP-007-R7).

Mutation check: flooring the shader's coverage at 0.001 instead of 0 ("small but not zero") fails 13
assertions in this suite.

## GPU time (CMP-007-S5; Mac, not device evidence)

`CMP007_BENCH=1 swift test -c release -Xswiftc -DDEBUG --package-path Packages/Compositor --filter
LayerMaskCompositeTests/testBenchMaskedFullScreenLayer`: one solid layer at 1920 × 1080
(`bgra8Unorm_srgb` output), whole frame (layer clear, composite, flash guard, output pass), 120 frames
after 10 warm-up frames, GPU start/end times. Not asserted.

| Case | Median (ms) | p95 (ms) |
|---|---|---|
| unmasked | 0.135 | 0.322 |
| circle | 0.153 | 0.172 |
| rounded rectangle | 0.087 | 0.116 |
| convex polygon (6 points) | 0.151 | 0.172 |
| concave polygon (6 points) | 0.151 | 0.179 |
| inverted circle | 0.107 | 0.136 |
| feathered ellipse | 0.107 | 0.108 |
| 32-point polygon, feathered | 0.437 | 0.482 |

The Mac's GPU clocks vary between cases (some masked cases measure below the unmasked one), so only
the 32-point polygon's cost (about +0.3 ms per 1080p frame for 32 edges per pixel) stands out.

## Scenes (`SceneMaskTests`, 5 tests, 0.04 s; host and Linux shape)

Each shape (an off-centre circle; a rotated, feathered rounded rectangle; an inverted, rotated
10-point star) with its transform: decode → encode byte for byte with no warnings; load reaches the
live stack with the same mask and transform; capture writes the same mask bytes; the saved form of a
default circle is fixed by a literal. A scene without a mask writes no `mask` field and stays
byte-identical; format version 1. An unknown shape (`heart` with extra keys) is kept verbatim through
decode → encode and load → capture, warned (`unsupportedMaskShape` at `$.layers[2].composite.mask.shape`),
a note in SCN-012's report, drawn unmasked; a live mask wins over the preserved one. Clamping warnings
for corner radius, feather, centre and scale; unknown keys dropped; malformed shapes refused. Polygons
with 2 points, 33 points or zero area drop the mask with one `droppedField` warning at
`$.layers[2].composite.mask`. QA-004's migration matrix and meta-test pass unchanged (no new version).

## Regression (after the change)

| Command | Result | Wall time |
|---|---|---|
| `swift test --package-path Packages/Compositor` | 272 tests, 3 skipped (benches), 0 failures (7.4 s in XCTest) | 22 s |
| same, Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) | 146 tests, 0 failures | 43 s (fresh build) |
| `swift test --package-path Packages/SceneFormat` | 98 tests, 0 failures (2.3 s) | 4 s |
| same, Linux shape | 98 tests, 0 failures (3.5 s) | 23 s (fresh build) |
| `swift test --package-path Packages/RenderGoldens` | 39 tests, 0 failures, no golden re-recorded | 19 s |
| `swift test --package-path Packages/ImportFuzz` | 15 tests, 0 failures | 37 s |
| `swift test --package-path Packages/ShowControl` | 31 tests, 0 failures | 17 s |
| `swift test --package-path Packages/SceneArchive` | 27 tests, 0 failures | 21 s |
| App unit tests (`-only-testing:projectM-iOSTests`, "CMP7 iPhone 17", iOS 27.2, deleted after) | 442 tests, 0 failures (16.8 s in XCTest), TEST SUCCEEDED; no new PosterBoard report (25 before and after) | 139 s (incl. build) |
| `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events` | OK | — |
| `test_scripts.py` | 151 tests OK (1 skipped) | 16 s |

## Not verified

- No device run (D1-D3); the GPU numbers are the Mac's.
- No UI: no screen edits layer properties (spec Clarifications).
- Ellipse distances with unequal scales are an estimate (sign exact), so a feathered ellipse's band
  is slightly uneven in width along its long axis; circles are exact.
