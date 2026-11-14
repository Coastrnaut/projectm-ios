# Quickstart: PERF-012

1. Package tests: `swift test --package-path Packages/Compositor --filter FrameIntervalHistogramTests` and
   `swift test --package-path Packages/Diagnostics --filter PerformanceReportTests`.
2. App: `xcodegen generate`, build-for-testing, then `test-without-building
   -only-testing:projectM-iOSTests/PerformanceReportAppTests -only-testing:projectM-iOSUITests/PerformanceReportUITests`
   on "PERF12 iPhone 17".
3. Device (`{device}`, D1): Settings → Performance → turn on the overlay, play 1 minute, Export performance report,
   save to Files; check the file against `contracts/performance-report.schema.json` and that it holds no names.
