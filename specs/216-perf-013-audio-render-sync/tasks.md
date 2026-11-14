# Tasks: PERF-013 Audio-render synchronization

**Input**: `specs/216-perf-013-audio-render-sync/` (spec, plan, research, data-model, contracts, quickstart)

Tests are part of the acceptance (spec S1-S4) and use injected clocks only (owner rule 7: short tests).

## Phase 1: Setup

- [ ] PERF-013-T01 Add `sessionSample: Int64 = 0` to `LiveBandFrameInfo` and fill it from `frame.time.sessionSample` in `LiveBandOutput.readLatest` in Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift

## Phase 2: Foundational (estimator)

- [ ] PERF-013-T02 Implement `AudioClockDriftEstimator` (1 s buckets of minimum residuals, ring capacity 64, ≥ 8 buckets, detect ≥ 50 ppm, clear < 25 ppm, step > 4 ms restarts the ring and holds the slope; preallocated) in Packages/Compositor/Sources/FrameTiming/AudioClockDriftEstimator.swift
- [ ] PERF-013-T03 Implement `FeatureFrameStamp`, `FeatureAgeSummary` and `FeatureAgeMeter` (Mutex; correction step ≤ 0.25 ms per frame toward the target, never past it; EMA 0.5 s; counting-session and app-session `FrameIntervalHistogram`s; anomalies; session reset) in Packages/Compositor/Sources/FrameTiming/FeatureAgeMeter.swift

## Phase 3: User Story 2 - Detect and correct clock drift (P1, the roadmap acceptance)

**Independent test**: injected clocks with ±500 ppm drift and deterministic one-sided jitter.

- [ ] PERF-013-T04 [US2] Acceptance tests: ±500 ppm detected, age error ≤ 1 ms from 10 s to 60 s, applied correction never past the true offset by > 1 ms, every step ≤ 0.25 ms; no drift → 0 corrections; a 100 ms latency step → no correction; session change resets; in Packages/Compositor/Tests/FrameTimingTests/AudioClockDriftTests.swift

## Phase 4: User Story 1 - See how old the audio on screen is (P1)

**Independent test**: a known injected age reads back within 0.1 ms; projectM reads "unavailable".

- [ ] PERF-013-T05 [P] [US1] Meter tests (known age → smoothed, p50, p95 within 0.1 ms; nil stamp → no sample; negative age → anomaly; counting session reset keeps the app-session histogram) in Packages/Compositor/Tests/FrameTimingTests/FeatureAgeMeterTests.swift
- [ ] PERF-013-T06 [US1] `FeatureAgeMeasured` protocol, conformance of the native, camera, photo, video and text hosts, and the per-frame helper (arrival = `MonotonicClock`, presentation = display-link target) in Apps/projectM-iOS/Visuals/FeatureAgeMeasuring.swift; one call after `readLatest` in each host's frame loop (Apps/projectM-iOS/Visuals/*VisualHost.swift, NativeSpectrumHost.swift)
- [ ] PERF-013-T07 [US1] `FeatureAgeAttachment` (attach to the shown visual while the overlay is shown, counting session per attach), overlay line per contract C2 after the frame-drop lines, verdict signposts per C3 (`DiagnosticsLog.audioSync`) in Apps/projectM-iOS/Coordinators/AppCoordinator+FeatureAge.swift, Apps/projectM-iOS/Coordinators/AppCoordinator+FrameStages.swift, Packages/Diagnostics/Sources/Diagnostics/Logging.swift; one stored property in Apps/projectM-iOS/Coordinators/AppCoordinator.swift
- [ ] PERF-013-T08 [US1] Report section `PerformanceReport.AudioSync` (optional; schema version 1 amended in specs/209-perf-012-performance-report/contracts/performance-report.schema.json and its test copy) and builder input in Packages/Diagnostics/Sources/Diagnostics/PerformanceReport.swift, Apps/projectM-iOS/Coordinators/PerformanceReportBuilder.swift, Apps/projectM-iOS/Coordinators/AppCoordinator+PerformanceReport.swift; schema test in Packages/Diagnostics/Tests/DiagnosticsTests/PerformanceReportTests.swift
- [ ] PERF-013-T09 [US1] App tests: attachment follows the overlay and the visual, overlay line text (available, unavailable, offset, drift), report section present/absent in Apps/projectM-iOS/Tests/FeatureAgeAppTests.swift

## Phase 5: Polish

- [ ] PERF-013-T10 Linux shape: `swift build` of Compositor (FrameTiming) and VisualGenerators with the Linux flags; Diagnostics tests; repo checks (compliance, docs, motion, permission catalog, status events, script tests)
- [ ] PERF-013-T11 Type-check budget of the touched app files (no function > 300 ms, expression > 150 ms)
- [ ] PERF-013-T12 {device} D1: native visual, microphone, overlay on 5 minutes: age line < 100 ms, no drift verdict; export the performance report and check `audioSync` (spec S5)

## Dependencies

T01 → T06; T02 → T03 → T04, T05; T03 → T06 → T07 → T09; T03 → T08 → T09; T10-T11 after all; T12 last.

## Parallel examples

T04 and T05 (different test files); T08's Diagnostics part alongside T06.

## Implementation strategy

MVP = US2 (estimator + acceptance, T02-T04), then the age meter surface (US1), then polish.
