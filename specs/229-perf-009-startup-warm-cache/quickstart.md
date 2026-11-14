# Quickstart: PERF-009 Startup warm cache

1. Package tests (host; LocalPortability and PresetLibrary also on Linux in CI):
   `swift test --package-path Packages/LocalPortability --filter 'WarmCache|LaunchTimeline'`,
   `swift test --package-path Packages/PresetLibrary --filter PresetLibraryWarmStart`,
   `swift test --package-path Packages/VisualGenerators --filter NativePipelineArchive`.
   Expect: every key-field change → stale and rebuilt; damaged payload → rebuilt; warm load `built == false`;
   archive hit with `.failOnBinaryArchiveMiss`; changed source → archive not opened and Metal misses.
2. App unit tests on the iOS 27.2 simulator: `-only-testing:projectM-iOSTests/WarmStartCacheTests`.
3. Device (D1) `{device}`: `python3 scripts/run_device_tests.py build`, then
   `python3 scripts/run_device_tests.py warmstart --device D1 --repeat 10`; record the cold and warm medians of
   `libraryReadyMs`, `libraryLoadMs` and `chooserMs` in `docs/test-reports/performance.md` (PERF-009 section).
   A `--simulator <udid>` rehearsal is labelled not evidence.
4. Instruments (Points of Interest): intervals "WarmStart library" and "WarmStart pipeline archive" with the outcome.
