# Test Report: FX-015 Vignette

Spec: `specs/305-fx-015-vignette` (ADR-0116). Run 2026-11-15 on the Mac Studio (Xcode 27.2) and the feature's own
iOS 27.2 simulator ("FX15 iPhone 17", deleted afterwards). Simulator results are never device evidence.

## Roadmap acceptance: "Center brightness stays unchanged at zero intensity"

| Proof | Test | What it asserts |
|-------|------|-----------------|
| Zero intensity = original frame (shader) | `VignetteCompositeTests.testVignetteOffAndZeroIntensityAreBitIdenticalAtCentreAndCorners` | Seeded random premultiplied content (37 × 29) through the real compositor: off, and on at intensity 0 with softness 0.1/0.5/0.9 and centres (0.5, 0.5), (0, 1), (0.8, 0.2), give raw half-float stack results equal to the input (centre and the four corners checked by name) and identical screen output; no pass ran, no picture held |
| Zero intensity = original frame (CPU) | `VignetteModelTests.testVignetteZeroIntensityIsExactIdentityAtCentreAndCorners` | Reference equals the input for 9 softness × centre cases; the factor is exactly 1 at the centre and the four corners |
| Zero intensity = original frame (scenes) | `VignetteSceneGoldenTests.testVignetteZeroIntensityRendersExactlyAsNoChain` | The golden plasma scene with an intensity-0 or a disabled `fx.vignette` entry equals the scene without a chain (`ImageDiff .exact`) |
| Centre unchanged at any intensity | `VignetteCompositeTests.testVignetteCentreIsExactAndBrightnessFallsToEveryCorner`, `VignetteModelTests.testVignetteCentreIsExactAtAnyIntensityAndCornersDarken` | Uniform grey (48 × 36) at intensity 0.3 and 1, softness 0.1/0.5/0.9: the four middle pixels are bit-exact; brightness never rises along 25 steps to each corner; every corner is darker; alpha kept |
| Monotonic falloff | same, and `VignetteModelTests.testVignetteFalloffIsMonotonicAlongRaysToEveryCorner` | The factor never rises along rays to all four corners and ends near 1 − intensity |
| Centre control | `VignetteCompositeTests.testVignetteCentreControlMovesTheUnchangedRegion`, `VignetteModelTests.testVignetteCentreControlMovesTheClearCore` | Centre (0.25, 0.5): the unchanged pixels are centred within 1 px of the new centre, the pixel there is exact, the left edge is brighter than the right |
| Reference and finite | `VignetteCompositeTests.testVignetteMatchesTheReferenceAndStaysFinite`, `VignetteModelTests.testVignetteOutputsAreFiniteAndNeverBrighter` | Random content with an HDR pixel (60000) and a transparent one: every GPU output is finite, never brighter than its input, within 2⁻⁹ relative of the CPU reference, and bit-exact wherever the factor is 1 |
| Order and pool | `VignetteCompositeTests.testVignetteOrderFoldsColorBeforeItAndThePictureIsReturned` | Standard order runs the grade pass before the vignette; vignette-first does not; off returns the picture |
| Scene round trip | `VignetteSceneEntryTests` (2), `VignetteSceneGoldenTests.testVignetteSaveReloadPersistsValuesAndDarkensOnlyTheEdges` | `fx.vignette` round-trips byte-identically, clamps and reports bad values, a disabled vignette saves nothing, older lists read with it last and encode byte-identically; a reloaded scene renders the identical picture, its middle pixels equal the plain scene's 8-bit output and its corners are under half as bright |

## Runs

| Suite | Where | Result |
|-------|-------|--------|
| Compositor (`swift test`) | Mac host (real Metal device) | 755 tests, 0 failures, 10 skipped as before (12 new; 27.5 s of tests) |
| Compositor, no-Metal shape (`-DCOMPOSITOR_NO_METAL`) | Mac host | `VignetteModelTests` 7/7, `OutputEffectOrderTests` pass |
| SceneFormat | host | 220 tests, 0 failures (2 new; 2.4 s) |
| RenderGoldens | host | 115 tests, 0 failures, 1 skipped (on-demand soak) (2 new; existing goldens unchanged; 14.9 s) |
| LibraryBackup | host | 88 tests, 0 failures |
| App unit tests (`projectM-iOSTests`) + `EffectChainUITests` | own simulator | 1354 tests, 0 failures (60.5 s), incl. `VignetteSettingTests` 5/5, `SettingsTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests`; `EffectChainUITests` 12.1 s |
| `VignetteUITests` | own simulator | 1 test, 18.3 s |
| Repo checks | host | compliance, docs, motion policy, permission catalog, status events OK; 186 script tests OK; `check_privacy_manifest` and `check_network_symbols` OK on the Debug simulator app |
| PosterBoard reports | `~/Library/Logs/DiagnosticReports` | 25 before, 25 after (none new) |

## Type-check budget

The new app files (`VignetteSetting`, `VignetteSection`, `AppCoordinator+Vignette`) raise no
`-warn-long-function-bodies=300` / `-warn-long-expression-type-checking=150` warning. The build flagged about 20
existing bodies at 286-385 ms (all near 300 ms under a heavily loaded host), among them `AppCoordinator.init` (578 ms;
FX-015 adds one line) and `EffectChainView.body` (321 ms; FX-015 changed no line in it).

## Open

- FX-015-T15 `{device}`: on D1, the Photo visual with Vignette at intensity 100 % and softness 10 % and 90 % and the
  centre moved; note the frame rate with and without it.
