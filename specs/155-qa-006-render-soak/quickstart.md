# Quickstart: QA-006 Render Soak Test

## A. Verdict logic (host and Linux shape)

```bash
swift test --package-path Packages/Compositor --filter RenderSoakVerdictTests
swift test --package-path Packages/Compositor --filter RenderSoakVerdictTests -Xswiftc -DCOMPOSITOR_NO_METAL
```

Expected: flat and noisy samples pass, a ramp fails `memorySlope`, a step fails `memoryBound`, too
few cycles is inconclusive, errors and baseline drift fail.

## B. Short scene soak and negative controls (host)

```bash
swift test --package-path Packages/RenderGoldens --filter RenderSoakTests
```

Expected: `testDefaultSoakIsBoundedAndErrorFree` passes (30 s simulated, 60 switches) and prints the
report path; both leak controls pass by asserting the soak failed with the named rules.

## C. Simulator (QA6, iOS 27.2)

```bash
cd Packages/RenderGoldens && xcodebuild build-for-testing test-without-building -scheme RenderGoldens \
  -destination id=<udid> -only-testing:RenderGoldensTests/RenderSoakTests CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180
cd Packages/ANGLERendering && xcodebuild ... -only-testing:ANGLERenderingTests/ProjectMPresetSoakTests
```

## D. Long soak on demand

```bash
python3 scripts/run_render_soak.py --seconds 600                  # host, scene soak
python3 scripts/run_render_soak.py --seconds 600 --simulator <udid> --angle
```

Prints each report's verdict and path; exit 1 on a failure. The device run (QA-006-S6) is the final
QA phase's `{device}` task.
