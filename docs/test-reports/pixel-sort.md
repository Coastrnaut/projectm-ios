# Test report: FX-011 Pixel sorting approximation

Feature `specs/310-fx-011-pixel-sorting`, ADR-0121. Run 2026-11-15 on the Mac Studio (Xcode 27.2), branch
`feature/fx-011`, own simulator "FX11 iPhone 17" (iOS 27.2, deleted afterwards). Simulator results are not device
evidence.

## Roadmap acceptance: "Threshold changes ordering; worst-case frame budget is enforced"

Definitions (spec Clarifications): a segment is a maximal run of pixels with finite Rec. 709 luminance ≥ threshold
inside a fixed tile of `span` pixels; it is stably sorted dark to bright; other pixels stay. The workload is
W × H × span steps, capped at B = 132,710,400 (7680 × 4320 × 4) by reducing the span, else skipping the pass; one
compute dispatch per active frame.

`Packages/Compositor/Tests/CompositorTests/PixelSortCompositeTests.swift`, through the real Metal compositor
(`encodeScene` or `composite(into:)`, half-float pixels compared exactly):

| Test | Asserts | Result |
|------|---------|--------|
| `testThresholdChangesOrderingAndTheGPUEqualsTheReference` | 37 × 21 gray picture, span 8 (partial last tiles), horizontal and vertical, thresholds 0.5 and 0.2: GPU output equals the CPU reference exactly, every segment non-decreasing, non-qualifying pixels untouched, each tile a permutation, the two thresholds give different outputs, one dispatch | pass |
| `testRandomContentStaysFiniteAndEachTileIsAPermutation` | random premultiplied content with HDR pixels, spans 4 and 64: finite, sorted segments, untouched others, permutation per tile | pass |
| `testOffIsBitIdenticalWithNoDispatch` | off: scene and screen output bit-identical to no effect, no dispatch, no picture; a 1-pixel-high frame is too small for a vertical sort | pass |
| `testEveryActiveFrameEncodesOneDispatchWithinTheBudget` | three frames: dispatch count 1, 2, 3; effective span 64; workload W × H × 64 ≤ B | pass |
| `testALoweredBudgetShortensTheSpanOrSkipsThePass` | budget W·H·8 + 7: span 8 used and output = reference at span 8; budget W·H·4 − 1: zero dispatches, one skip counted, output identical to off | pass |
| `testOrderFoldsColorBeforeItAndThePictureIsReturned` | Color before it is folded first; off returns the picture; source in the archive key; position after Lens distortion, Vignette last | pass |

`PixelSortModelTests` (5, no GPU; also run with `-DCOMPOSITOR_NO_METAL`, the Linux shape): clamping and span snapping;
the budget plan over 39 × 39 frame sizes from 1 to 16384 per side × 5 spans × 2 directions (workload ≤ B, the largest
admissible span, skip exactly when span 4 does not fit); 1080p → 64, 1290 × 2796 → 32, 4K → 16, 8K → 4, larger
skipped; reference behaviour and threshold dependence.

## Other suites

| Command | Result | Time |
|---------|--------|------|
| `swift test --package-path Packages/Compositor` | CompositorTests 783 tests, 0 failures (10 skipped); every bundle passes | 68 s |
| `swift test --package-path Packages/SceneFormat` | 226 tests, 0 failures (PixelSortSceneEntryTests 2) | 41 s |
| `swift test --package-path Packages/RenderGoldens` | 123 tests, 0 failures (1 skipped; PixelSortSceneGoldenTests 2) | 17 s |
| `swift test --package-path Packages/LibraryBackup` | 88 tests, 0 failures | 27 s |
| App unit tests on the own simulator (PixelSortSettingTests, LibraryBackupAppTests, LibraryEraseAppTests, SettingsTests, EffectChainSettingTests, Chromatic/Directional/Radial/Echo/Vignette/LensDistortion setting tests) | 58 tests, 0 failures | 79 s run |
| `PixelSortUITests.testPixelSortControls` | pass | 25.0 s |
| `EffectChainUITests.testReorderEffects` | pass | 22.9 s |
| `python3 scripts/test_scripts.py` | 186 tests OK (1 skipped) | 16 s |
| `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events` | OK | |
| `check_privacy_manifest`, `check_network_symbols` on the Debug simulator app | OK | |

PosterBoard reports: 25 before, 25 after.

## Open

- FX-011-T16 `{device}`: GPU frame time on D1 with Pixel sort on (span 32 and 64, both directions), and on a 4K external
  display if available.
