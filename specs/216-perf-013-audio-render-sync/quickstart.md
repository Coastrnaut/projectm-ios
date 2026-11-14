# Quickstart: PERF-013

1. `swift test --package-path Packages/Compositor --filter 'AudioClockDriftTests|FeatureAgeMeterTests'` — acceptance
   (±500 ppm detected and corrected: ≤ 3 ms from 15 s, ≤ 2 ms from 30 s; no drift → no correction, steps ignored, steps ≤ 0.25 ms).
2. `swift test --package-path Packages/Diagnostics --filter PerformanceReportTests` — `audioSync` validates.
3. App unit tests on "PERF13 iPhone 17": `-only-testing:projectM-iOSTests/FeatureAgeAppTests`.
4. `{device}` D1: native visual, microphone, overlay on for 5 minutes: the age line shows < 100 ms and no drift
   verdict; export the performance report and check `audioSync`.
