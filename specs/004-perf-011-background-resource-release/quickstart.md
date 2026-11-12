# Quickstart: validating PERF-011

Prerequisites: `Build/ProjectM.xcframework` and `Build/ANGLEFrameworks` (see CLAUDE.md), and for
the ANGLE tests the engine's test presets (`git submodule update --init Vendor/projectM`).

## A. Host (any Mac, no simulator)

```bash
swift test --package-path Packages/PresentationLifecycle
swift test --package-path Packages/Diagnostics
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py
```

Expected: all tests pass; both scripts print OK.

## B. Simulator (iOS 27.2, a simulator no other job is using)

```bash
UDID=<simulator udid>
(cd Packages/ANGLERendering && xcodebuild -scheme ANGLERendering -destination "id=$UDID" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO test > /tmp/angle.log 2>&1); grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:" /tmp/angle.log
(cd Packages/Rendering && xcodebuild -scheme Rendering-Package -destination "id=$UDID" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO test > /tmp/rendering.log 2>&1); grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:" /tmp/rendering.log
```

Expected: TEST SUCCEEDED for both. Simulator results prove state transitions only.

## C. App unit tests (needs the preset submodules; main session after the merge)

`xcodegen generate`, then the `projectM-iOS` scheme's unit tests, at least
`LifecycleCoordinatorTests` and `IdleTimerPolicyTests`.

## D. Devices `{device}` (final stage, not part of this run)

1. D1, System/App Capture running, visualizer on screen. Record with Instruments (GPU, Allocations,
   Points of Interest). Press Home. Expect the "Presentation" signpost with `active 2 -> 0`, GPU
   time for the app at zero from then on, and a lower memory footprint after 10 s (S7).
2. Return to the app. Expect `active 0 -> 2` and frames within 2 s (S7).
3. D1-D3: open the app switcher from the visualizer, then return. The card and the first frame
   show the visualization (S8). Repeat with lock and unlock, and with a rotation while away.
4. Pull down Control Center over the visualizer: the picture keeps moving (S5).
