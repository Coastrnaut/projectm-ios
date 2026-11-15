# Test Report: FX-007 Directional Blur

Spec: `specs/295-fx-007-directional-blur` (ADR-0106). Run 2026-11-15 on the Mac Studio (Xcode 27.2) and the feature's
own iOS 27.2 simulator ("FX7 iPhone 17", deleted afterwards). Simulator results are never device evidence.

## Roadmap acceptance: "Angle zero blurs horizontally and radius zero is identity"

| Proof | Test | What it asserts |
|-------|------|-----------------|
| Radius zero is identity | `DirectionalBlurCompositeTests.testOffAndZeroRadiusAreBitIdenticalOnRandomContent` | Seeded random premultiplied content (37 × 29): off and on-with-radius-0 (30°) give identical raw half-float stack results, equal to the uploaded input, and identical screen output; no pass ran, no picture held |
| Radius zero (scenes) | `EffectChainSceneTests.testZeroBlurRendersExactlyAsNoChain` | The golden plasma scene with a zero or disabled `fx.directionalBlur` entry equals the scene without a chain (`ImageDiff .exact`) |
| Angle zero is horizontal | `DirectionalBlurCompositeTests.testAngleZeroSpreadsAVerticalLineOnlyAlongItsRows` | 300 × 300 frame, an 8-px vertical white line, 2% radius (6 px) at 0°: every pixel of every other row is unchanged; each line row keeps its energy within 1%, spreads left and right, nothing beyond 6 px |
| 90° is vertical | `DirectionalBlurCompositeTests.testNinetyDegreesSpreadsAHorizontalLineOnlyAlongItsColumns` | The same with a horizontal line at 90°: other columns unchanged, column energy within 1% |
| Fixed tap budget | `DirectionalBlurModelTests.testKernelHasSixteenSymmetricTapsWithUnitWeight`, `testReferenceReadsSixteenSamplesPerPixelAtEveryRadius`; `DirectionalBlurCompositeTests.testShaderDeclaresTheFixedTapBudgetAndThePictureIsReturned` | 16 symmetric taps from −radius to +radius, Gaussian weights summing to 1 and independent of the radius; the CPU reference reads exactly 16 samples per pixel at 0.1%, 1% and 2%; the shader declares `cmp_dirblur_taps = 16` and loops over that constant |
| Samples inside the frame | `DirectionalBlurModelTests.testEverySamplePositionIsInsideTheFrame`; `DirectionalBlurCompositeTests.testMaximumRadiusStaysInRangeAndMatchesTheReference` | Every tap position (corners and centre, five angles, maximum radius) lies in the frame; on random content at 0°, 45°, 90°, 150° every output value lies within the frame's range and the GPU is within 1/256 of the CPU reference |
| Non-finite values | `DirectionalBlurModelTests.testNonFiniteNeverSpreadsAndZeroIsIdentity` | A NaN/Inf pixel passes through; its neighbours stay finite with renormalised weights |
| Chain, scenes, presets | `SceneEffectChainTests` (2 new), `EffectChainSceneTests.testBlurSaveReloadPersistsValuesAndPicture`, `DirectionalBlurSettingTests` | Round trip, clamp and report, older lists unchanged and byte-identical, the golden picture is identical after save/reload and differs from no blur; app scene and preset paths |

## Runs

| Suite | Where | Result |
|-------|-------|--------|
| Compositor (`swift test`) | Mac host | all pass, 0 failures (13 new; 1:22) |
| Compositor, Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) | Mac host | builds with tests |
| SceneFormat | host | 211 tests, 0 failures (2 new) |
| RenderGoldens | host | 108 tests, 0 failures, 1 skipped as before (2 new; existing goldens unchanged) |
| LibraryBackup | host | 88 tests, 0 failures |
| App unit tests (`projectM-iOSTests`) | own simulator | 1302 tests, 0 failures (66 s) |
| `DirectionalBlurUITests` | own simulator | 1 test, 18.8 s |
| `EffectChainUITests`, `ChromaticSplitUITests` | own simulator | 13.5 s, 22.4 s, pass |
| Repo checks | host | compliance, docs, motion policy, permission catalog, status events OK; 186 script tests OK |
| Privacy manifest, network symbols | Debug simulator app | OK |

PosterBoard crash reports: 25 before and 25 after the simulator runs.

The type-check budget run (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`) reports no FX-007
function or expression; the warnings it shows are in files this feature does not touch.

## Open

- FX-007-T17 `{device}`: on D1, the Photo visual with the blur at 2% and 45°: the streak looks right and the frame rate
  with and without the blur is recorded.
