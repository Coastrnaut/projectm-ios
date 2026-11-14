# Test report: CMP-009 Luma key

Feature: `specs/220-cmp-009-luma-key` (branch `feature/cmp-009`). Host: the Mac Studio (build machine of record),
Xcode 27.2, Swift 6.4.2; simulator "CMP9 iPhone 17" (iOS 27.2). The Mac was heavily shared during the run (load
average up to about 380). Simulator results are not device evidence; no device run was made.

## Baseline (CMP-009-T01, before any change, commit `31da9491`)

`swift test --package-path Packages/Compositor`: CompositorTests 543 tests (8 skipped), 0 failures.
`swift test --package-path Packages/SceneFormat`: 175 tests, 0 failures. PosterBoard reports: 26.

## CPU reference (`LayerLumaKeyReferenceTests`, 8 tests, 0.002 s; host and Linux shape)

Rec. 709 luma of the displayed (sRGB-encoded) straight colour: black 0, white 1, primaries 0.2126 / 0.7152 / 0.0722,
displayed mid-grey 0.5; premultiplied input at half alpha gives the opaque luma; alpha 0, non-finite and negative
channels read 0; over-bright clamps to 1. Keep factor 0 inside the range, 1 beyond the softness band, 0.5 half way
across it on both sides; a 4,096-step sweep is monotonic on both sides (0 violations); softness 0 is a hard cut;
invert is the exact complement; clamping (low, high 0…1, softness 0…0.5, non-finite defaults, −0 stored as 0) and a
reversed range swapped. Linux shape: `swift build --build-tests` with `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL
-DANALYSIS_NO_ACCELERATE` succeeded and the 8 reference tests pass.

## Acceptance: GPU read-back (`LayerLumaKeyCompositeTests`, 10 GPU tests + 1 opt-in bench)

Fixture layer 160 × 96 (half floats, premultiplied linear): columns 0-47 black, 48-63 near-black (linear 0.004, luma
≈ 0.05), 64-111 a bright patch (0.8, 0.6, 0.4), 112-159 a grey ramp. Black key (low 0, high 0.1, softness 0):

| Region | Pixels | Check | Violations | Worst |
|---|---|---|---|---|
| black + near-black | 6,144 | layer alpha ≤ 1/255 | 0 | 0.0 |
| bright patch | 4,608 | colour and alpha = unkeyed draw within 1/255 | 0 | 0.0 |

Draw counts: `maskedDraws` 1, `blendDraws` 0 (no extra pass). Also: over an opaque backdrop the dark columns show the
backdrop within 1/255; softness (key 0…0.1, softness 0.2) over a full-width grey ramp: 160 samples monotonic and
within 1/255 of the CPU reference (worst 0.00042), more than 40 columns inside the ramp; at opacity 0.5 the same
pixels are keyed and the patch reads alpha 0.5; invert keeps black and removes the patch; key × circle shape × linear
gradient equals the product of the three within 0.01; `multiply` takes the key inside `cmp_blend` (`blendDraws` 1;
keyed black shows the backdrop instead of darkening it); a CMP-005-transformed layer (move 0.1, scale 0.85, rotation
0.4) keyed = unkeyed × keep(unkeyed) at every pixel within 2/255, 500+ fully keyed pixels; a key that keys nothing
draws like no key within 1/255; a key added at apply shows on the next frame with no layer re-created, no new
pictures and no new prepare, and removing it is bit-identical to unkeyed.

Mutation check: replacing the shader's keep factor with 1 made 8 of the 10 GPU tests fail (the acceptance: 6,144
dark pixels at alpha 1); the blend-mode test then used `screen`, which hides the key on black, so it was changed to
`multiply`. Restored afterwards.

## Goldens (`LumaKeyGoldenTests`, 1 test + integrity)

`luma-key-black` (black band, orange and green patches, grey ramp; key 0…0.15, softness 0.1, over opaque dark blue),
both QA-002 resolutions. Recorded and then compared on the macOS host and the iOS 27.2 simulator: identical (0 pixels
changed; the two platform classes have the same pixel hashes). 24 KB. RenderGoldens suite on the host: 85 tests
(1 skipped), 0 failures, 37 s.

## Scenes (`SceneLumaKeyTests`, 3 tests; host)

The black key and a non-default inverted key, each alone and with a circle shape and a linear gradient: decode →
encode byte-identical with no warnings, the live stack gets the key, load → capture keeps the composite byte for
byte; the saved form `{"high":0.1,"invert":false,"low":0.0,"softness":0.05}`; no field without a key, format version
1; out-of-range numbers clamped (`valueClamped` per field), a reversed range swapped (`valueClamped` at the key),
unknown keys dropped (`droppedField`), missing fields read the black key, malformed values refused. SceneFormat suite:
178 tests, 0 failures (including QA-004's meta-test).

## App (iOS 27.2 simulator)

- `LayerLumaKeyEditTests` 5, `LayerGradientEditTests` 7, `LayerInspectorTests` 10, `LayerInspectorRenderTests` 2,
  `SceneHistoryCoordinatorTests` 4, `LibraryBackupAppTests/testIncludedKeysAndFolderNamesAgreeWithTheStores` 1:
  29 tests, 0 failures (no UserDefaults key added).
- UI test `testLumaKeyToggleDragAndUndo`: turn the key on ("Undo Photo Luma Key On"), Key High shows 0.10, drag it
  up (one step, "Undo Photo Luma Range …"), undo restores 0.10 and the toggle is the step before: passed in 40.7 s
  under load average about 365 (the existing gradient UI test took 66.9 s in the same conditions; its CMP-008 report
  gives 29.9 s at load 60-110). Over the 30 s budget only because of the shared load.
- Type-check budget flags (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`): no warning in
  any file this feature touched (one in the untouched `SceneHistoryControls.swift`, 235 ms under load).
- `check_privacy_manifest.py` and `check_network_symbols.py` on the Debug simulator app: OK.

## GPU time (CMP-009-S5; Mac, not device evidence)

`CMP009_BENCH=1`, Debug, 1920 × 1080 `bgra8Unorm_srgb`, 120 frames after 10 warm-up, GPU start/end times, under
load average about 365 (noisy: the keyed case ran faster than the unkeyed one; not a measurement of the key's cost):

| Case | Median (ms) | p95 (ms) |
|---|---|---|
| no key | 0.549 | 0.552 |
| black key | 0.301 | 0.685 |
| black key × circle × radial | 0.412 | 0.413 |

D1 measurement is open (`{device}`, CMP-009-T19).

## Full Compositor suite after the change

562 CompositorTests (9 skipped: the opt-in benches and device-only tests), 0 failures.

## Repo checks

`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`: OK.
`test_scripts.py`: 164 tests, OK (1 skipped).

## PosterBoard

26 reports before, 26 after; none from "CMP9 iPhone 17".
