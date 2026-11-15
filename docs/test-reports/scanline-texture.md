# Test Report: FX-018 Scanline texture

Spec: `specs/312-fx-018-scanline-texture` (ADR-0123). Run 2026-11-15 on the Mac Studio (Xcode 27.2) and the feature's
own iOS 27.2 simulator ("FX18 iPhone 17", deleted afterwards, with its derived data). Simulator results are never
device evidence.

## Roadmap acceptance: "Spacing is consistent in pixels and disabled state is identity"

"Consistent in pixels" (spec Clarifications): for every spacing p, thickness t and picture size, the darkened rows
(columns when vertical) are exactly {c : c mod p < t}, every darkened pixel is the input × the same factor
1 − intensity, every other pixel is bit-identical, and the pitch measured from the rendered picture equals p for every
pair of bands.

| Proof | Test | What it asserts |
|-------|------|-----------------|
| Disabled = original frame (compositor) | `ScanlinesCompositeTests.testScanlinesOffAndZeroIntensityAreBitIdentical` | Seeded random premultiplied content (37 × 29) through the real compositor: off, disabled at intensity 1, and on at intensity 0 with spacings 2/3/16, thickness 1/15 and both orientations give raw half-float results equal to the input and identical screen output; no pass ran, no picture held |
| Shader at intensity 0 = identity | `ScanlinesCompositeTests.testScanlinesShaderRunAtZeroIntensityIsBitIdentical` | `cmp_scanlines` run directly (outside the compositor's skip) on random content with an HDR pixel returns its input bit for bit, horizontal and vertical |
| Disabled = original frame (scenes) | `ScanlinesSceneGoldenTests.testScanlinesZeroIntensityRendersExactlyAsNoChain` | The golden plasma scene with an intensity-0 or a disabled `fx.scanlines` entry equals the scene without a chain (`ImageDiff .exact`) |
| Every spacing, every size | `ScanlinesCompositeTests.testScanlinesEverySpacingDarkensExactlyThePredictedRowsAtEverySize` | Uniform input at 37 × 23 (odd), 61 × 97 (portrait), 129 × 45 (landscape); spacings 2…16, thickness varied in 1…p − 1, horizontal and vertical (90 frames): each row compared with `memcmp` against the predicted all-dark or all-unchanged row; dark count equals the predicted count; the first band starts at pixel 0; measured pitch = p for every pair of bands; one band per period |
| 4K | `ScanlinesCompositeTests.testScanlinesSpacingIsConsistentAt4K` | 3840 × 2160: spacings 2, 3, 16 horizontal and 3 vertical, the same exact checks (0.34 s) |
| Rule (CPU) | `ScanlinesModelTests.testScanlinesRuleIsAnchoredAtIndexZeroForEverySpacing` | For spacings 2…16 and three thicknesses each, the dark rows are {y : y mod p < t}, row 0 dark, row t the first untouched, pitch = p; vertical uses columns |
| Reference and finite | `ScanlinesCompositeTests.testScanlinesMatchesTheReferenceAndStaysFinite`, `ScanlinesModelTests` | Random content with an HDR pixel (60000) on a dark row and a transparent pixel: untouched pixels bit-identical to the reference, darkened pixels within one half-float step of it, every output finite, never brighter, alpha kept |
| Outputs, order and pool | `ScanlinesCompositeTests.testScanlinesReachTheScreenFoldColorBeforeAndReturnThePicture` | The screen output (`composite(into:)`) has exactly rows y mod 4 < 2 darker and the others equal to the off output; standard order runs the grade pass before the scanlines, scanlines-first does not; off returns the picture |
| Scene round trip | `ScanlinesSceneEntryTests` (2), `ScanlinesSceneGoldenTests.testScanlinesSaveReloadPersistsValuesAndBlacksOutExactlyThePredictedLines` | `fx.scanlines` round-trips byte-identically, clamps and reports bad values, disabled saves nothing, older lists read with it after Vignette and encode byte-identically; a reloaded scene renders the identical picture with the predicted rows (spacing 3) and columns (spacing 7, thickness 3) exactly black at intensity 1 and every other pixel equal to the plain scene's 8-bit output |

### GPU rounding (research FX-018-D5)

The first run expected the CPU's round-to-nearest half for darkened pixels and failed by one step: 0.5 × 0.7 was
stored as half `0x3599` where the nearest is `0x359A`. The Mac's GPU float-to-half render-target store does not round
to nearest. The tests now take the darkened value from pixel (0, 0) (always in a line), require it within one half step
of the reference, and require every other darkened pixel to be bit-identical to it (one factor) and every untouched
pixel bit-identical to the input. Byte sizes of textures are never asserted.

## Runs

| Suite | Where | Result |
|-------|-------|--------|
| Compositor (`swift test`) | Mac host (real Metal device) | CompositorTests 787 tests, 0 failures, 10 skipped as before (11 new: model 5, GPU 6; 56 s of tests, 83 s wall incl. build); the other targets of the package pass |
| Compositor, no-Metal shape (`-DCOMPOSITOR_NO_METAL`, own scratch path) | Mac host | `ScanlinesModelTests` 5/5, `OutputEffectOrderTests` 5/5 |
| SceneFormat | host | 226 tests, 0 failures (2 new; 2.8 s) |
| RenderGoldens | host | 128 tests, 0 failures, 1 skipped (on-demand soak) (2 new; existing goldens unchanged; 17.4 s) |
| LibraryBackup | host | 88 tests, 0 failures (10.1 s) |
| App unit tests (13 suites: `ScanlinesSettingTests`, `SettingsTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests`, `EffectChainSettingTests`, `AccessibleParameterTests`, the Chromatic/Directional/Radial/Echo/Mosaic/Lens/Vignette setting tests) | own simulator | 70 tests, 0 failures (0.66 s) |
| `ScanlinesUITests`, `EffectChainUITests` | own simulator | 2 tests, 0 failures: 13.4 s and 17.7 s |
| Repo checks | host | `test_scripts` (186 tests OK), `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events` OK; `check_privacy_manifest` and `check_network_symbols` OK on the Debug app |

The first app run failed two assertions that spell the effect-order summary (`EffectChainSettingTests`,
`ChromaticSplitSettingTests`); both now end in "→ Scanlines" and pass.

## Type-check budget

The app was built with `-warn-long-function-bodies=300` and `-warn-long-expression-type-checking=150`. No warning names
a new file (`ScanlinesSetting`, `ScanlinesSection`, `AppCoordinator+Scanlines`) or the FX-018 additions. The build
flagged about 25 existing bodies at 300-500 ms under a loaded host (among them `AppCoordinator.init`, 499 ms, which
gained one line, and `EffectChainSection.body`, 313 ms, whose code is unchanged), as in earlier feature reports.

## PosterBoard

25 `PosterBoard-*.ips` reports before and 25 after; none written during this feature's runs.

## Not verified here

- FX-018-T16 `{device}`: on D1, the look on a real screen (even lines, no crawl or flicker at spacings 2, 3, 16,
  intensity 100 %, both orientations) and the frame rate with and without scanlines.
- CI's Linux job builds the model; it was exercised here only in the Linux shape on the Mac.

## Merge with FX-011 Pixel sort (2026-11-15)

`autonomous/integration` (FX-011 integrated) was merged into `feature/fx-018`, keeping both sides. The order is now
… Edge outline → Lens distortion → Pixel sort → Vignette → Scanlines. Two FX-011 assertions that Vignette is last
(`PixelSortCompositeTests`, `PixelSortSettingTests`) now assert that Vignette directly follows Pixel sort. After the merge:
Compositor package 1259 tests in all bundles, 0 failures (CompositorTests 798, 10 skipped); SceneFormat 228;
RenderGoldens 130 (1 skipped); LibraryBackup 88; the full app unit bundle 1388 tests, 0 failures (58.9 s), and
`ScanlinesUITests` (14.6 s), `PixelSortUITests` (13.0 s) and `EffectChainUITests` (15.5 s) passed on a new own
simulator ("FX18b iPhone 17", deleted afterwards); `test_scripts` (186), `check_compliance` and `validate_docs` OK.
PosterBoard reports: 25 before, 25 after.
