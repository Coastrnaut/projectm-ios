# Test report: CMP-006 Aspect fitting

Feature: `specs/101-cmp-006-aspect-fitting` (branch `feature/cmp-006`). Host: the Mac Studio (build
machine of record), Xcode 27.2, Swift 6.4.2. Simulator results are not device evidence; no device
run was made.

## Baseline (CMP-006-T01, before any change)

`swift test --package-path Packages/Compositor`: 233 tests, 1 skipped (CMP-004 bench), 0 failures,
7.3 s. `swift test --package-path Packages/SceneFormat`: 89 tests, 0 failures, 2.6 s.

## Geometry (CPU; `LayerFitGeometryTests`, 8 tests, host and Linux shape)

Contents 300 × 500 (portrait) and 1000 × 600 (landscape); outputs 390 × 844 (portrait) and
1920 × 1080 (landscape); 16 cases.

| Mode | Rule checked in all 4 content × output cases | Pixel aspect | Result |
|---|---|---|---|
| fill | visible ≤ 1 on both axes, one axis exactly 1; content rectangle covers 0…1 | 1 (1e-12) | pass |
| fit | visible ≥ 1 on both axes; content rectangle inside 0…1 | 1 (1e-12) | pass |
| stretch | output corners show content corners (0,0) and (1,1) | ≠ 1 where the aspects differ | pass |
| pixelAccurate | 1 output pixel per content pixel; origin on a whole output pixel | 1 (1e-12) | pass |

Also: the anchor (centre, top centre, top left, right middle) lands on the same output fraction in
the portrait and the landscape output for fill, fit and pixelAccurate (1e-9; pixelAccurate within half
an output pixel), with the mode rule still holding; a top-anchored fill has offset 0 in both
orientations. A content pixel stays square through a rotated, uniformly scaled CMP-005 transform
(equal lengths and orthogonal within 1e-9). Video: with no fit, `VideoPictureGeometry` equals the
previous `CameraPictureGeometry` fill for all four rotations at both output sizes (1e-6); a sideways
portrait clip in fit has bars left and right in landscape; pixelAccurate is 1:1 on the upright size.

## GPU read-back (`LayerFitCompositeTests`, 6 GPU tests + 1 opt-in bench)

A 24 × 40 marker photo (yellow top band; red, green, blue, white quadrants) through a stack entry's
fit, rendered by one compositor into 72 × 144 (portrait) and then 128 × 72 (landscape). Every output
pixel whose content coordinate is at least 1 content pixel (pixelAccurate: 0.4, i.e. every pixel)
from a marker or content edge is compared with the colour `LayerFitPlacement` predicts, within 2/255.

| Mode | Portrait: compared / transparent / wrong | Landscape: compared / transparent / wrong |
|---|---|---|
| fill | 7564 / 0 / 0 | 6372 / 0 / 0 |
| fit | 7080 / 960 / 0 | 7076 / 4880 / 0 |
| stretch | 7320 / 0 / 0 | 6588 / 0 / 0 |
| pixelAccurate | 9940 / 8980 / 0 (all 960 photo pixels exact) | 8820 / 7860 / 0 |

Other GPU cases, all passing on the Mac host: a top-anchored fill shows the yellow band on the top
output row in portrait and landscape (a mutation that ignores the anchor fails it); fit with the
`screen` blend mode over a backdrop matches the CMP-004 CPU reference in both orientations; fill with
a CMP-005 transform (move, scale 0.75, rotation 0.3) matches "fit first, then transform"; a fit
change at `apply` shows from the next frame with no layer re-created, no new picture and no reload,
the left-anchored fit puts the red edge on the left and the bar on the right; a fit on a layer
without `LayerFitting` changes nothing; a rotated portrait video (upright 48 × 64) in fit has
transparent bars left/right in landscape and top/bottom in portrait. The flash guard is never reset in these tests:
`lastFlashGain` stays 1.

## GPU time (CMP-006-S5; a measurement, not device evidence, not an assertion)

`CMP006_BENCH=1 swift test -c release -Xswiftc -DDEBUG --package-path Packages/Compositor --filter LayerFitCompositeTests/testBenchGPUTimePerMode`
(1080 × 1920 photo into 1920 × 1080, whole frame: photo pass, composite, flash guard, output into
`bgra8Unorm_srgb`; 120 frames after 10 warm-up frames, `gpuEndTime − gpuStartTime`):

| Mode | Median | p95 |
|---|---|---|
| fill | 0.139 ms | 0.336 ms |
| fit | 0.224 ms | 0.567 ms |
| stretch | 0.161 ms | 0.638 ms |
| pixelAccurate | 0.083 ms | 0.228 ms |

Every mode is the same single photo pass (no pass added); differences are the texels sampled and
mip levels touched.

## Scene format (`SceneFitTests`, 4 tests)

Every mode with an anchor survives decode → validate → load → capture → encode; unknown `"tile"` is
kept (decode → encode and load → capture), warned (`unsupportedFitMode`, path
`$.layers[2].composite.fit.mode`), listed by SCN-012 as a note, drawn as the default; a live fit wins
over a preserved one; anchor components clamp with `valueClamped`; `fit` without `mode`, with a
non-string mode, as a string or with a non-object anchor is malformed; a scene without a fit writes
no `fit` field and decodes → encodes byte-identically.

## Regression (after the change)

| Command | Result | Wall time |
|---|---|---|
| `swift test --package-path Packages/Compositor` | 248 tests, 2 skipped (benches), 0 failures (5.2 s in XCTest) | 14 s |
| same, Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) | 130 tests, 0 failures | 5 s |
| `swift test --package-path Packages/SceneFormat` (and Linux shape) | 93 tests, 0 failures (2.1 s / 2.3 s) | 13 s |
| `swift test --package-path Packages/RenderGoldens` | 39 tests, 0 failures, no golden re-recorded | 14 s |
| `swift test --package-path Packages/ImportFuzz` | 15 tests, 0 failures | 15 s |
| `swift test --package-path Packages/ShowControl` | 31 tests, 0 failures | 12 s |
| `swift test --package-path Packages/SceneArchive` | 27 tests, 0 failures | 12 s |
| App unit tests (`-only-testing:projectM-iOSTests`, "CMP6 iPhone 17", iOS 27.2) | 430 tests, 0 failures (13.5 s in XCTest); no new PosterBoard report | 109 s (incl. build) |
| `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog` | OK | — |
| `test_scripts.py` | 147 tests OK (1 skipped) | 13 s |

## Not verified

- No device run (D1-D3): rotation, external display and recording on hardware are covered by the
  output-size-independent geometry and the GPU portrait → landscape read-back, not by a device.
- No UI: no screen edits layer properties (spec Clarifications).
- The camera layer is unchanged (CAM-007 owns it; follow-up in the spec).
