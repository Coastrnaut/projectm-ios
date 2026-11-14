# Data model: PERF-012

- **FrameIntervalHistogram** (FrameTiming): `resolutionMs` 0.1, `bucketCount` 2500, `buckets [UInt32]`, `count`,
  `sumMs`, `maxMs`, `longFrameThresholdsMs` [25, 50, 100] with exact `longFrames` counts. `record(seconds:)` ignores
  non-finite or ≤ 0 values. `percentile(_ p)` → nil when `count` is 0, else the upper edge of the bucket holding rank
  `max(1, ceil(p × count))`, capped by `maxMs` (the last bucket reports `maxMs`).
- **FrameIntervalRecorder** (FrameTiming): `record(seconds:)`, `snapshot()`; never reset (session = app launch).
- **PerformanceReport** (Diagnostics, schema version 1): `schemaVersion`, `kind`, `exportedAt`, `device`, `app`,
  `session {durationSeconds, visual, overlayShown}`, `frames {sampleCount, measuredSeconds, resolutionMs, p50Ms…p99Ms,
  maxMs (absent when no sample), longFrames [{thresholdMs, count}]}`, `frameDrops?` (PERF-007), `frameTimings?`
  (PERF-001/002/003), `states {current, timeline (≤ 200), truncated}`, `resources {texturePool?, memory}`.
- **StateSample**: `atSeconds`, `thermal` (nominal/fair/serious/critical/unknown), `lowPower`, `profile`
  (standard/followLowPowerMode/batterySaver/unknown), `maxFramesPerSecond`, `renderScale`. A sample is appended only
  when a value differs from the previous one; the 201st change sets `truncated` and is dropped.
- **Visual kind**: projectM, native, camera, photo, video, text, none, unknown.
