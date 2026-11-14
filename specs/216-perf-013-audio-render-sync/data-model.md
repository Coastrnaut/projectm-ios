# Data model: PERF-013

## FeatureFrameStamp (FrameTiming)
- `session: UInt64` — ANL-016 session; a change resets the estimate (R7).
- `sequence: UInt64` — bus item ID; a new value is a first read (an observation).
- `sessionSample: Int64` — end of the analysed window.
- `busHostNanoseconds: UInt64` — the bus's host time.

## AudioClockDriftEstimator (value, preallocated)
- Configuration: `sampleRate` 44,100; `bucketSeconds` 1; `capacity` 64; `minimumBuckets` 8; `detectPPM` 50;
  `clearPPM` 25; `stepNanoseconds` 4,000,000.
- State: open bucket (start e, min r, e at min); ring of closed bucket minima; `slopePPM: Double?`; `detected: Bool`;
  `restarts: Int`.
- `observe(sessionSample:residualNanoseconds:)`; `target(atSessionSample:) -> Double` (ns).

## FeatureAgeMeter (class, Mutex)
- `maxStepNanoseconds` 250,000; `smoothingSeconds` 0.5.
- `beginCountingSession()`; `frame(_ stamp: FeatureFrameStamp?, arrivalNanoseconds:, presentationNanoseconds:)`.
- `summary() -> FeatureAgeSummary` (counting session), `appSummary()` (since launch).

## FeatureAgeSummary
- `count`, `smoothedMs?`, `p50Ms?`, `p95Ms?`, `maxMs?`, `anomalies`, `driftDetected`, `driftPPM?`,
  `correctionMs`, `detections`, `steps`.

## PerformanceReport.AudioSync (Diagnostics)
- `sampleCount`, `p50Ms?`, `p95Ms?`, `maxMs?`, `driftDetected`, `driftPpm?`, `detections`; absent without samples.
