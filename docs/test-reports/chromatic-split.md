# Test Report: FX-006 Chromatic Split

Spec: `specs/293-fx-006-chromatic-split` (ADR-0104). Run 2026-11-15 on the Mac Studio (Xcode 27.2) and the feature's own
iOS 27.2 simulator ("FX6 iPhone 17", deleted afterwards). Simulator results are never device evidence.

## Roadmap acceptance: "Zero offset is exact pass-through and edges stay within frame bounds"

| Proof | Test | What it asserts |
|-------|------|-----------------|
| Zero is exact | `ChromaticSplitCompositeTests.testOffAndZeroAmountAreBitIdenticalOnRandomContent` | Seeded random premultiplied content (37 × 29): off and on-with-amount-0 give identical raw half-float stack results, equal to the uploaded input, and identical screen output; no pass ran, no picture held |
| Zero is exact (scenes) | `EffectChainSceneTests.testZeroSplitRendersExactlyAsNoChain` | The golden renderer's plasma scene with a zero or disabled `fx.chromatic` entry equals the scene without a chain (`ImageDiff .exact`) |
| Edges in bounds (whole pixels) | `ChromaticSplitCompositeTests.testWholePixelShiftsReadOnlyInsideTheFrameAndKeepTheBorder` | 100 × 100 frame with 396 unique border colours around a uniform interior, 2 px split at 0°, 90°, 180°, 270°: every output R, G, B value is a value present inside the frame (no zero from an out-of-frame read, no wrap), alpha 1, every border pixel unchanged; GPU equals the CPU reference exactly |
| Edges in bounds (fractional, radial) | `ChromaticSplitCompositeTests.testFractionalAndRadialSplitsStayInsideTheFrame` | 64 × 40 bordered frame at 45° and radial (max amount): every channel within the frame's value range, border ring unchanged, GPU within 1/512 of the CPU reference |
| Sample maths | `ChromaticSplitModelTests` (7 tests, CPU, Linux-buildable) | Clamp/wrap, activity, linear direction and fade (0 at the border, half at 1 px, full beyond the band), radial centre 0 and ≤ amount, every sample position inside the frame for five angles and radial, whole-pixel shift, alpha = max, non-finite pixels pass through and a weight-0 neighbour never leaks, inactive = input |
| R and B shift | `ChromaticSplitCompositeTests.testRedAndBlueShiftByTwoPixels` | A white column and row: red exactly 2 px right / blue 2 px left at 0°, red 2 px up / blue 2 px down at 90°, green in place |
| Order and pool | `ChromaticSplitCompositeTests.testOrderFoldsColorBeforeTheSplitAndThePictureIsReturned` | Standard order runs the grade pass before the split; Trails → Split → Color does not; the two differ with a saturation grade; off returns the picture |

## Runs

| Suite | Where | Result |
|-------|-------|--------|
| Compositor (`swift test`) | Mac host | all pass (CompositorTests 672 incl. 12 new, 10 skipped as before) |
| Compositor (`xcodebuild test`) | own iOS 27.2 simulator | 1123 tests, 0 failures; chromatic GPU tests ran (not skipped) |
| Compositor, Linux shape (`-DCOMPOSITOR_NO_METAL …`) | Mac host | builds |
| SceneFormat | host and simulator | 207 tests, 0 failures (2 new) |
| RenderGoldens | host and simulator | 106 tests, 0 failures (2 new; existing goldens unchanged) |
| LibraryBackup | host | 88 tests, 0 failures |
| App unit tests (`projectM-iOSTests`) | own simulator | 1287 tests, 0 failures (68 s) |
| `ChromaticSplitUITests` | own simulator | 1 test, 19.2 s |
| `EffectChainUITests` | own simulator | 1 test, 13.5 s |
| Repo checks | host | compliance, docs, motion policy, permission catalog, status events OK; 186 script tests OK |
| Privacy manifest, network symbols | Debug simulator app | OK |

PosterBoard crash reports: 25 before and 25 after the simulator runs.

The type-check budget run reports `AppCoordinator.init(defaults:externalDisplay:memoryPressure:)` at 381 ms (limit
300 ms); FX-006 adds two one-line statements to it (the setting and its `connect` call). No FX-006 function or
expression appears in the warnings.

## Open

- FX-006-T18 `{device}`: on D1, the Photo visual with the split at 2% (linear and radial): fringes look right and the
  frame rate with and without the split is recorded.
