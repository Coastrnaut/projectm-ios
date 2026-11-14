# Test report: CMP-008 Gradient masks

Feature: `specs/207-cmp-008-gradient-masks` (branch `feature/cmp-008`). Host: the Mac Studio (build machine of
record), Xcode 27.2, Swift 6.4.2; simulator "CMP8 iPhone 17" (iOS 27.2). The Mac was heavily shared during the run
(load average 60-350). Simulator results are not device evidence; no device run was made.

## Baseline (CMP-008-T01, before any change, commit `d518a943`)

`swift test --package-path Packages/Compositor`: CompositorTests 519 tests (7 skipped), 0 failures.
`swift test --package-path Packages/SceneFormat`: 168 tests, 0 failures. PosterBoard reports: 25.

## CPU reference (`LayerGradientReferenceTests`, 10 tests, 0.003 s; host and Linux shape)

Each stop's alpha exactly at its position (the later stop wins at a hard step); clamping before the first and after
the last stop; a dense sweep (256 samples per segment) of four stop lists (rising, falling, mixed, hard step): 0
monotonicity violations, every sample within its two stops' alphas; equal positions give a hard step; stable sort
and clamping of stops; refusals (1 stop, 9 stops, zero-length linear); geometry clamping (points −10…10, radius
0.01…20, non-finite reads the default); the linear parameter is a projection in pixels (diagonal isolines
perpendicular); a radial gradient stays round on 160 × 90 and 90 × 160 pictures (1e-9); the editor defaults.

## Acceptance: GPU read-back (`LayerGradientCompositeTests`, 7 GPU tests + 1 opt-in bench, 0.8 s)

A solid opaque layer (linear premultiplied 0.8, 0.4, 0.2, 1) over transparent in a 160 × 96 `rgba16Float` output;
output alpha = gradient alpha. Every pixel of the axis is sampled; per segment of adjacent stops alpha must not move
against the stops' direction by more than 1/255, and every sample must match the CPU reference within 1/255.

| Case | Samples | Monotonic violations | Worst step against | Reference violations | Worst reference error |
|---|---|---|---|---|---|
| linear, 5 stops (rise, fall, rise, flat), centre row | 160 | 0 | 0.00000 | 0 | 0.00049 |
| radial, 4 stops, ray from the centre | 160 | 0 | 0.00000 | 0 | 0.00049 |

Also: every row of the linear gradient is bit-identical and colour is premultiplied by the same alpha; each stop
(on a pixel centre) reads its alpha within 1/255; every pixel of the radial picture matches the reference (round);
all-opaque stops draw bit-equal to no gradient; gradient × circle: 0 outside pixels with alpha ≠ 0, the rest within
0.01 of coverage × alpha; a CMP-005 transform (move 0.15, scale 0.9, rotation 0.3) matches the reference at the
inverse-mapped layer pixel (≤ 0.01, 5,000+ pixels); normal mode adds no pass (`maskedDraws` 1, `blendDraws` 0);
`screen` takes the gradient inside `cmp_blend` (same acceptance, 0 violations); a change at apply shows on the next
frame with no layer re-created, no new pictures and no new prepare, and removing it is bit-identical to unmasked.

Mutation check: replacing the shader's linear interpolation with a sine (non-monotonic) makes the acceptance fail
(54 and 117 violations in one test alone); restored afterwards.

## Goldens (`GradientMaskGoldenTests`, 2 tests + integrity)

`gradient-mask-linear` (diagonal, 4 stops) and `gradient-mask-radial` (3 stops × a rounded rectangle), both QA-002
resolutions, over an opaque dark backdrop (straight-alpha PNGs did not round-trip through ImageIO on the iOS
simulator). Recorded and then compared on the macOS host and the iOS 27.2 simulator: identical (0 pixels changed).
120 KB. RenderGoldens suite on the host: 79 tests, 0 failures.

## Scenes (`SceneGradientMaskTests`, 5 tests, 0.04 s; host and Linux shape)

Linear and radial, each alone and with a circle shape: decode → encode byte-identical, no warnings, the live stack
gets both, load → capture keeps the composite byte for byte; no field without a gradient, format version 1; an
unknown kind (`conic`) is kept verbatim through decode, load and capture, warned (`unsupportedMaskShape` at
`…gradientMask.kind`, a note in SCN-012's report), not drawn while its shape still applies, and a live gradient wins;
clamping (centre, radius, stop position and alpha) and re-sorting warn `valueClamped`; unknown keys (also inside a
stop) `droppedField`; no stops, 1 stop, 9 stops and a zero-length linear drop the gradient with `droppedField`;
malformed values are refused. SceneFormat suite: 173 tests (Linux shape 172), 0 failures, including QA-004's
meta-test. ImportFuzz 17, SceneArchive 36, ShowControl 89: 0 failures.

## App (iOS 27.2 simulator)

- `LayerGradientEditTests` 7 tests, `LayerInspectorTests` 10, `LibraryBackupAppTests/testIncludedKeysAndFolderNamesAgreeWithTheStores` 1:
  0 failures (no UserDefaults key added). History, layer and autosave suites: 51 tests, 0 failures.
- UI test `testGradientStopsCanBeAddedEditedAndUndone`: choose Linear, Add Stop (3 stops; the new stop's alpha
  0.50 is the gradient's own), drag stop 2's alpha up (one undo step, "Undo Photo Gradient Stop 2 Alpha …"),
  undo restores 0.50 and the add is the step before: passed in 29.9 s (load average about 110 → 60; earlier
  runs under load 230-350 took 36-66 s). The two existing inspector UI tests still pass (18.8 s, 18.9 s).
- Type-check budget flags: no warning in any file this feature touched (the warnings listed are in untouched files,
  all about 220 ms under the shared load).
- `check_privacy_manifest.py` and `check_network_symbols.py` on the Debug simulator app: OK.

## GPU time (CMP-008-S5; Mac, not device evidence)

`CMP008_BENCH=1`, Debug, 1920 × 1080 `bgra8Unorm_srgb`, 120 frames after 10 warm-up, GPU start/end times:

| Case | Median (ms) | p95 (ms) |
|---|---|---|
| no gradient | 0.550 | 0.566 |
| linear, 5 stops | 0.712 | 0.738 |
| radial, 8 stops | 0.819 | 0.855 |
| radial 8 stops × circle shape | 0.975 | 1.013 |

D1 measurement is open (`{device}`, CMP-008-T19).

## Full Compositor suite after the change

537 CompositorTests (8 skipped), 0 failures in the feature's tests. One unrelated failure in one run:
`FrameRecordingTests.RecordingQualityFixtureTests.testMaxMatchesItsProfile` (average bit rate 50.9 Mb/s vs 40 ± 10,
the hardware encoder under load); it passed on rerun and does not touch masks.

## PosterBoard

25 reports before, 26 after. The new report is dated 14:52, before this feature's simulator existed, and does not
name it; no crash from "CMP8 iPhone 17".
