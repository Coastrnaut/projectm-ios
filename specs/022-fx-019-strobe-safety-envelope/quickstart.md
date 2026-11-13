# Quickstart: validating FX-019

Run from the repository root. Simulator: iOS 27.2 iPhone Air. Simulator and Mac GPU results are
evidence for the logic only, never for devices (Constitution X).

## A. Pure envelope (any OS, seconds)

```bash
swift test --package-path Packages/FlashSafety
```

Expected: every acceptance sequence (white/black 60 Hz and 10 Hz, red/black, 50 % gray steps, slow
fade, single flash, seeded noise, local tile strobe) reports at most 4 transitions per 1 s window
with Reduce flashing on and 6 with it off; the fade and (off) the single flash are unchanged; runs
repeat identically. The test log prints the acceptance matrix.

## B. Native visuals (Mac host, Linux shape and Metal)

```bash
swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
swift test --package-path Packages/VisualGenerators
```

Expected: VIS-001 and FX-001 Reduce-flashing tests pass; `StrobeEnvelopeRenderTests` (Metal,
64 × 64) prints measured transitions per window within the budget.

## C. projectM frames (simulator)

```bash
(cd Packages/ANGLERendering && xcodebuild test -scheme ANGLERendering -destination 'id=<udid>' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO > ../../.build/scratch/angle.log 2>&1)
(cd Packages/Rendering && xcodebuild test -scheme Rendering-Package -destination 'id=<udid>' ... > ../../.build/scratch/rendering.log 2>&1)
```

Expected: `FlashLimiterTests` print the measured matrix (solid frames read back at 64 × 64) within
the budget and the GPU gain matches the Swift reference within 0.01.

## D. Device `{device}`

RendererLab `RL_BACKEND=angle RL_MODE=flashcost` on D1 (T104 method): the pass costs at most 2 ms
per frame; now also note the frame rate with the setting off (the pass runs always).
