# Test Report: FX-008 Radial Blur

Spec: `specs/296-fx-008-radial-blur` (ADR-0107). Run 2026-11-15 on the Mac Studio (Xcode 27.2) and the feature's own
iOS 27.2 simulator ("FX8 iPhone 17", deleted afterwards). Simulator results are never device evidence.

## Roadmap acceptance: "Center remains stable while outer test points spread predictably"

| Proof | Test | What it asserts |
|-------|------|-----------------|
| Centre stable | `RadialBlurCompositeTests.testFocusIsStableAndOuterDotsStreakByDistanceTimesStrength` | 101 × 81 black frame with single white dots at the focus (50, 40) and at 8, 16, 32 px right, left, up and down; maximum strength (25%) through the real compositor: the focus pixel's raw half-float value is bit-identical to the input |
| Outer points spread predictably | same test | For each of the 12 outer dots, walking out along its ray from the focus, the lit run (≥ half a sample's weight) starts at the dot and ends within 1 px of d × 1.25 (10, 20, 40 px); nothing is lit just inward of the dot; every pixel more than 1 px from the focus row and column stays exactly black (streaks only along the rays) |
| Adjustable focus | `RadialBlurCompositeTests.testOffCentreFocusIsStableAndStreaksRadiateFromIt` | Focus at 25% across (pixel 25, 30 of 101 × 61): that pixel is bit-identical; the d = 32 dot streaks to 40 px right of the new focus and no further |
| Zero is exact | `RadialBlurCompositeTests.testOffAndZeroStrengthAreBitIdenticalOnRandomContent` | Seeded random premultiplied content (37 × 29): off and on-with-strength-0 give identical raw stack results equal to the input, identical screen output; no pass ran, no picture held |
| Zero is exact (scenes) | `EffectChainSceneTests.testZeroRadialBlurRendersExactlyAsNoChain` | The golden plasma scene with a zero or disabled `fx.radialBlur` entry equals the scene without a chain (`ImageDiff .exact`) |
| GPU = reference, in bounds | `RadialBlurCompositeTests.testGPUMatchesTheReferenceForCentreAndCornerFocus` | Random content, focus centred, at the top-left corner and at (1, 0.3): GPU within 1/128 of the exact-bilinear CPU reference; premultiplied colour never exceeds alpha |
| Sample maths, fixed taps | `RadialBlurModelTests` (7 tests, CPU, Linux-buildable) | Clamps and defaults; activity; 16 positions for every pixel and strength, sample 0 = the pixel; every sample inside the frame for five focus points including corners; spread 0 at the focus and linear (2, 4, 8 px); the reference streak of a point runs from d to d(1 + s); identity at zero, at the focus and for a non-finite pixel |
| Order and pool | `RadialBlurCompositeTests.testOrderFoldsColorBeforeTheBlurAndThePictureIsReturned` | Standard order runs the grade pass before the blur; blur-first does not; off returns the picture |

## Runs

| Suite | Where | Result |
|-------|-------|--------|
| Compositor (`swift test`) | Mac host (real Metal device) | all pass (CompositorTests 694 incl. 12 new, 10 skipped as before; 1 min 20 s) |
| Compositor, Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`, with tests) | Mac host | builds |
| SceneFormat | host | 211 tests, 0 failures (2 new) |
| RenderGoldens | host | 108 tests, 0 failures, 1 skipped (on-demand soak) (2 new; existing goldens unchanged) |
| LibraryBackup | host | 88 tests, 0 failures |
| App unit tests (`projectM-iOSTests`) | own simulator | 1302 tests, 0 failures (63 s) |
| `RadialBlurUITests` | own simulator | 1 test, 32.4 s and 35.7 s (see note) |
| `EffectChainUITests`, `ChromaticSplitUITests` | own simulator | pass (28.2 s, 40.0 s) |
| Repo checks | host | compliance, docs, motion policy, permission catalog, status events OK; 186 script tests OK |
| Privacy manifest, network symbols | Debug simulator app | OK |

Note on UI-test time: the host's load average was about 100 during the runs (parallel feature agents); FX-006's
`ChromaticSplitUITests`, 19.2 s in its own report, took 40.0 s in the same run, so `RadialBlurUITests` (the same shape:
launch, toggle, slider drag) is expected under 30 s on an idle host. Not re-measured idle.

The first app run found that CAM-005's `CameraFocusAppTests.testNotesAndNoStoredKey` forbids "focus" in stored keys;
the keys were renamed `settings.radialBlur.centerX`/`centerY` (spec Clarifications) and the full suite passed.

Type-check budget run: no FX-008 function or expression appears in the warnings (the listed ones are in untouched
files).

PosterBoard crash reports: 25 before and 25 after the simulator runs.

## Open

- FX-008-T18 `{device}`: on D1, the Photo visual with Radial blur at 25%, focus centred and moved: streaks radiate from
  the focus, and the frame rate with and without the blur is recorded.
