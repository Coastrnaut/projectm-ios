# Quickstart: PERF-001 validation

## Host and Linux (pure timer, compositor GPU, diagnostics)

```bash
swift test --package-path Packages/Compositor --filter FrameTimingTests          # acceptance, ring, rejection
swift test --package-path Packages/Compositor --filter CompositorStageTimingTests # Mac GPU: finite composite/output
swift test --package-path Packages/Diagnostics                                    # export round trip + schema
PERF001_BENCH=1 swift test --package-path Packages/Compositor --filter testBenchCostPerFrame  # on-demand cost
```

Expected: the acceptance test reports exactly the pipeline labels with the injected durations and
"unavailable" GPU values.

## Simulator (own simulator "PERF1 iPhone 17", iOS 27.2)

Build for testing, then `-only-testing:projectM-iOSTests/FrameStageAppTests` and
`-only-testing:projectM-iOSUITests/FrameStageOverlayUITests` (< 30 s): the overlay shows "stages ms" and
the native visual's labels. Simulator numbers are never evidence.

## Device (`{device}`, D1)

Install the measurement build and launch with `PROJECTM_AUTORUN=perf001`; copy
`Documents/automation-perf001-*.json` (frame timings in diagnostics format, fps with the timer off and on).
