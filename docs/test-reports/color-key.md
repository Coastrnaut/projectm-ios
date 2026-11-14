# Test report: CMP-010 Color key

Feature: `specs/230-cmp-010-color-key` (branch `feature/cmp-010`). Host: the Mac Studio (build machine of record),
Xcode 27.2, Swift 6.4.2; simulator "CMP10 iPhone 17" (iOS 27.2). The Mac was heavily shared during the run (load
average about 390-460). Simulator results are not device evidence; no device run was made.

## Baseline (CMP-010-T01, before any change, commit `96ee68c7`)

`swift test --package-path Packages/Compositor`: CompositorTests 569 tests (9 skipped), 0 failures.
`swift test --package-path Packages/SceneFormat`: 178 tests, 0 failures. PosterBoard reports: 26.

## Design (spec Clarifications, research CMP-010-D1 to D4)

Distance in the Rec. 709 Y′CbCr chroma plane of the displayed straight colour (sRGB-encoded with the CMP-004 curve,
CMP-009's luma weights); keep = 0 within the tolerance, a linear ramp over the feather, 1 beyond. One `float4 chroma`
row (key Cb, key Cr, tolerance, 1 + feather; w 0 = no key) appended to the CMP-007 mask block (`CMPMask` 432 bytes);
the keep factor multiplies shape coverage × gradient alpha × luma keep in `cmp_over_masked` and `cmp_blend`; no new
pass or pipeline. No spill suppression (it would recolour kept pixels) and no invert.

## CPU reference (`LayerColorKeyReferenceTests`, 5 tests, 0.003 s; host and Linux shape)

Neutrals have chroma (0, 0); green's chroma is (−0.7152/1.8556, −0.7152/1.5748); pure red Cr 0.5, pure blue Cb 0.5;
premultiplied input at half alpha gives the opaque chroma; alpha 0 and non-finite channels read 0. Under the green
key the green patch keeps 0 and red, blue, white, skin (0.87, 0.67, 0.55) and dark green (0, 0.3, 0) keep 1, each more
than 0.05 beyond tolerance + feather. Ramp keep 0 at the tolerance, 0.5 half way across the feather, 1 beyond; a
1,001-step sweep from green to grey is monotonic (0 violations); feather 0 is a hard cut; clamping and non-finite
defaults (green key), −0 stored as 0. Linux shape: `swift test` with `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL
-DANALYSIS_NO_ACCELERATE` builds every target and the 5 reference tests pass.

## Acceptance: GPU read-back (`LayerColorKeyCompositeTests`, 9 GPU tests + 1 opt-in bench)

Fixture layer 160 × 96 (half floats, premultiplied linear, displayed colours): columns 0-31 green (0, 1, 0), then 16
columns each of red, blue, white, skin (0.87, 0.67, 0.55) and dark green (0, 0.3, 0), then 112-159 a ramp from green to
mid-grey. Green key (`greenKey`: tolerance 0.2, feather 0.1):

| Region | Pixels | Check | Violations | Worst |
|---|---|---|---|---|
| green patch | 3,072 | layer alpha ≤ 1/255 | 0 | 0.0 |
| red, blue, white, skin, dark green | 7,680 | colour and alpha = unkeyed draw within 1/255, alpha 1 | 0 | 0.0 |

Draw counts: `maskedDraws` 1, `blendDraws` 0 (no extra pass). Also: over an opaque backdrop the green columns show the
backdrop within 1/255 and red stays; feather (tolerance 0.15, feather 0.25) over a full-width green-to-grey ramp: 160
samples monotonic and within 1/255 of the CPU reference (worst 0.00047), more than 40 columns inside the ramp; at
opacity 0.5 the same pixels are keyed and red reads alpha 0.5; colour key × luma key × circle shape × linear gradient
equals the product within 0.01 (with 100+ pixels where both keys are partial); `screen` takes the key inside
`cmp_blend` (`blendDraws` 1; keyed green shows the backdrop instead of brightening it); a CMP-005-transformed layer
keyed = unkeyed × keep(unkeyed) at every pixel within 2/255, 500+ fully keyed pixels; a magenta key that keys nothing
draws like no key within 1/255; a key added at apply shows on the next frame with no layer re-created, no new pictures
and no new prepare, a colour change alone (green → red key) shows on the next frame, and removing it is bit-identical.

Mutation check: replacing the shader's colour keep with 1 made 8 of the 9 GPU tests fail (all but "keys nothing").
Restored afterwards.

## Goldens (`ColorKeyGoldenTests`, 1 test + integrity)

`color-key-green` (green band, red and skin patches, green-to-grey ramp; tolerance 0.2, feather 0.15, over opaque dark
blue), both QA-002 resolutions. Recorded and then compared on the macOS host and the iOS 27.2 simulator: identical
(0 pixels changed; both platform classes have the same pixel hashes). RenderGoldens suite on the host: 87 tests
(1 skipped), 0 failures, 15 s.

## Scenes (`SceneColorKeyTests`, 3 tests; host)

The green key and a non-default key, each alone and with a black luma key and a circle shape: decode → encode
byte-identical with no warnings, the live stack gets the key, load → capture keeps the composite byte for byte; the
saved form `{"blue":0.0,"feather":0.1,"green":1.0,"red":0.0,"tolerance":0.2}`; no field without a key, format version 1;
out-of-range numbers clamped (`valueClamped` per field), unknown keys dropped (`droppedField`), missing fields read the
green key, malformed values refused. SceneFormat suite: 181 tests, 0 failures (including QA-004's meta-test).

## App (iOS 27.2 simulator)

- `LayerColorKeyEditTests` 6, `LayerLumaKeyEditTests` 5, `LayerGradientEditTests`, `LayerInspectorTests` (one help
  entry per parameter), `LayerInspectorRenderTests`, `SceneHistoryCoordinatorTests`,
  `LibraryBackupAppTests/testIncludedKeysAndFolderNamesAgreeWithTheStores`: 35 tests, 0 failures (no UserDefaults key
  added).
- UI test `testColorKeyToggleDragAndUndo`: turn the key on ("Undo Photo Color Key On"), the colour picker is found by
  `layerControl.colorKeyColor` with the accessible name "Key Color", Color Tolerance shows 0.20, drag it up (one step,
  "Undo Photo Color Tolerance …"), undo restores 0.20 and the toggle is the step before: passed in 43.1 s under load
  average about 390 (CMP-009's equivalent took 40.7 s at load 365). Over the 30 s budget only because of the shared load.
- Type-check budget flags (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`): no warning in
  any file this feature touched (warnings only in untouched files, inflated by the load).
- `check_privacy_manifest.py` and `check_network_symbols.py` (19 images) on the Debug simulator app: OK.

## GPU time (CMP-010-S5; Mac, not device evidence)

`CMP010_BENCH=1`, Debug, 1920 × 1080 `bgra8Unorm_srgb`, 120 frames after 10 warm-up, GPU start/end times, under load
average about 400 (noisy: the keyed cases ran faster than the unkeyed one; not a measurement of the key's cost):

| Case | Median (ms) | p95 (ms) |
|---|---|---|
| no key | 0.549 | 1.124 |
| green key | 0.323 | 0.545 |
| green key × black key | 0.371 | 0.616 |

D1 measurement is open (`{device}`, CMP-010-T19).

## Full Compositor suite after the change

584 CompositorTests (10 skipped: the opt-in benches and device-only tests), 0 failures.

## Repo checks

`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`: OK.
`test_scripts.py`: 174 tests, OK (1 skipped).

## PosterBoard

26 reports before, 26 after; none from "CMP10 iPhone 17".
