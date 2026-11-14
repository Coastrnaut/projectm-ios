# Quickstart: SHOW-003

1. `swift test --package-path Packages/PerformanceControl --filter QuantizedCueStepTests`
   — boundary math, once-only, replace/cancel/keep, no-tempo fallback.
2. App unit tests on "SHOW3 iPhone 17": `-only-testing:projectM-iOSTests/ShowCueQuantizerAcceptanceTests`
   — synthetic 120 BPM grid, injected clock: Next mid-beat moves once at the next beat and never again; Bar waits for
   the bar; no tempo moves at once with "Cue changed now, no tempo"; a timed advance waits for the beat.
3. UI test `QuantizedCueStepsUITests`: Settings › Quantize cue steps offers Off/Beat/Bar, and with Beat and no tempo
   Next still moves the show (fallback).
4. Manual (optional, simulator UI only): tap tempo four times on the performance pad, set Beat, press Next cue and see
   "Cue queued for the next beat" until the cue changes.
