# Quickstart: PERF-007 Frame drop telemetry

1. Counter (host, and Linux shape):
   `swift test --package-path Packages/Compositor --filter FrameDropCounterTests`
   Expect the acceptance sequence counts exactly, duplicates once, stale events excluded.
2. Export: `swift test --package-path Packages/Diagnostics --filter FrameDropsExportTests` (round trip, absent keys, schema).
3. App (simulator "PERF7"): build-for-testing, then
   `test-without-building -only-testing:projectM-iOSTests/FrameDropAppTests`.
4. Manual: Settings → Performance overlay on, open the visualizer; the overlay shows `frames device: …`; with
   projectM the presented values read `unavailable`.
5. `{device}` D1 with an external display: `frames external` counts after connecting; device counter stops.
