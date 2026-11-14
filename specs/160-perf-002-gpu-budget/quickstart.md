# Quickstart: PERF-002 GPU budget meter

## A. Pure logic (host, Linux shape)

```bash
swift test --package-path Packages/Compositor --filter FrameTimingTests
swift test --package-path Packages/Compositor --filter FrameTimingTests \
  -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
swift test --package-path Packages/Diagnostics
```

Expected: FrameBudgetTests pass (composite-only flag, spy frame counts equal, 60/120/30 fps deadlines,
unavailable never flagged, hysteresis, lines).

## B. App (simulator "PERF2", iOS 27.2)

Build for testing, then run `projectM-iOSTests/FrameBudgetAppTests` and
`projectM-iOSUITests/FrameBudgetOverlayUITests` (< 30 s). The UI test launches the circular spectrum with
the overlay on and `-uitestSlowStage render:40`, and expects `over budget: render cpu 40.00 ms > ` in the
overlay label. Simulator output is never evidence for numbers.

## C. Device `{device}`

With the overlay on, on D1, run the automation mode `perf001` and check the `frameTimings.budget` object;
record whether any pass is flagged at the device's normal load. Pending device.
