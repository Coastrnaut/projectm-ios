# Tasks: PERF-013 Audio-render synchronization

**Input**: `specs/216-perf-013-audio-render-sync/` (spec, plan, research, data-model, contracts, quickstart)

Tests are part of the acceptance (spec S1-S4) and use injected clocks only (owner rule 7: short tests).

## Phase 1: Setup

- [X] PERF-013-T00 Create the feature simulator "PERF13 iPhone 17" (iOS 27.2) and run `xcodegen generate` in the worktree (delete the simulator and derived data at the end) — Verified 2026-11-14: simulator 71344F44 created (`xcrun simctl create`), `xcodegen generate` OK
- [X] PERF-013-T01 Add `sessionSample: Int64 = 0` to `LiveBandFrameInfo` and fill it from `frame.time.sessionSample` in `LiveBandOutput.readLatest` in Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift — Verified 2026-11-14: app build on "PERF13 iPhone 17" (TEST BUILD SUCCEEDED); `swift build --package-path Packages/VisualGenerators` OK; FeatureAgeAppTests feed it through `FeatureFrameStamp`

## Phase 2: Foundational (estimator)

- [X] PERF-013-T02 Implement `AudioClockDriftEstimator` (1 s buckets of minimum residuals, ring capacity 64, ≥ 10 buckets, detect ≥ 50 ppm and ≥ 3 standard errors, clear < 25 ppm, a step > 10 ms starts a new segment intercept; preallocated) in Packages/Compositor/Sources/FrameTiming/AudioClockDriftEstimator.swift — Verified 2026-11-14: AudioClockDriftTests (7 pass, 0.09 s) via `swift test --package-path Packages/Compositor --filter 'AudioClockDriftTests|FeatureAgeMeterTests'`
- [X] PERF-013-T03 Implement `FeatureFrameStamp`, `FeatureAgeSummary` and `FeatureAgeMeter` (Mutex; correction step ≤ 0.25 ms per frame toward the target, never past it; EMA 0.5 s; counting-session and app-session `FrameIntervalHistogram`s; anomalies; session reset) in Packages/Compositor/Sources/FrameTiming/FeatureAgeMeter.swift — Verified 2026-11-14: FeatureAgeMeterTests (5 pass) and AudioClockDriftTests (7 pass)

## Phase 3: User Story 2 - Detect and correct clock drift (P1, the roadmap acceptance)

**Independent test**: injected clocks with ±500 ppm drift and deterministic one-sided jitter.

- [X] PERF-013-T04 [US2] Acceptance tests: ±500 ppm detected (four jitter seeds), age error ≤ 3 ms from 15 s and ≤ 2 ms from 30 s to 60 s, applied correction never past the true offset by > 2 ms, every step ≤ 0.25 ms; no drift → 0 corrections; a 100 ms latency step → no correction; session change resets; in Packages/Compositor/Tests/FrameTimingTests/AudioClockDriftTests.swift — Verified 2026-11-14: `swift test --package-path Packages/Compositor --filter AudioClockDriftTests`: 7 tests pass in 0.09 s

## Phase 4: User Story 1 - See how old the audio on screen is (P1)

**Independent test**: a known injected age reads back within 0.1 ms; projectM reads "unavailable".

- [X] PERF-013-T05 [P] [US1] Meter tests (known age → smoothed, p50, p95 within 0.1 ms; nil stamp → no sample; negative age → anomaly; counting session reset keeps the app-session histogram) in Packages/Compositor/Tests/FrameTimingTests/FeatureAgeMeterTests.swift — Verified 2026-11-14: `swift test --package-path Packages/Compositor --filter FeatureAgeMeterTests`: 5 tests pass
- [X] PERF-013-T06 [US1] `FeatureAgeMeasured` protocol, conformance of the native, camera, photo, video and text hosts, and the per-frame helper (arrival = `MonotonicClock`, presentation = display-link target) in Apps/projectM-iOS/Visuals/FeatureAgeMeasuring.swift; one call after `readLatest` in each host's frame loop (Apps/projectM-iOS/Visuals/*VisualHost.swift, NativeSpectrumHost.swift) — Verified 2026-11-14: TEST BUILD SUCCEEDED; FrameDropOverlayUITests (extended) shows "audio age 37.8 ms p95 97.2 ms" on the native visual in the simulator (label only, not evidence), 15.4 s
- [X] PERF-013-T07 [US1] `FeatureAgeAttachment` (attach to the shown visual while the overlay is shown, counting session per attach), overlay line per contract C2 after the frame-drop lines, verdict signposts per C3 (`DiagnosticsLog.audioSync`) in Apps/projectM-iOS/Coordinators/AppCoordinator+FeatureAge.swift, Apps/projectM-iOS/Coordinators/AppCoordinator+FrameStages.swift, Packages/Diagnostics/Sources/Diagnostics/Logging.swift; one stored property in Apps/projectM-iOS/Coordinators/AppCoordinator.swift — Verified 2026-11-14: FeatureAgeAppTests (5 pass): attachment per overlay/visual, line text, one signpost per verdict change; overlay UI test shows the line
- [X] PERF-013-T08 [US1] Report section `PerformanceReport.AudioSync` (optional; schema version 1 amended in specs/209-perf-012-performance-report/contracts/performance-report.schema.json and its test copy) and builder input in Packages/Diagnostics/Sources/Diagnostics/PerformanceReport.swift, Apps/projectM-iOS/Coordinators/PerformanceReportBuilder.swift, Apps/projectM-iOS/Coordinators/AppCoordinator+PerformanceReport.swift; schema test in Packages/Diagnostics/Tests/DiagnosticsTests/PerformanceReportTests.swift — Verified 2026-11-14: PerformanceReportTests.testAudioSyncSectionValidatesAndIsAbsentWithoutSamples (Diagnostics 30 pass); FeatureAgeAppTests.testReportSectionPresentAndAbsent; PerformanceReportAppTests (6 pass); `python3 scripts/test_scripts.py` OK (schema copy equals the contract)
- [X] PERF-013-T09 [US1] App tests: attachment follows the overlay and the visual, overlay line text (available, unavailable, offset, drift), report section present/absent, the signpost fires once per verdict change (R10) in Apps/projectM-iOS/Tests/FeatureAgeAppTests.swift — Verified 2026-11-14: `xcodebuild test-without-building -only-testing:projectM-iOSTests/FeatureAgeAppTests` (+ PerformanceReportAppTests, FrameDropAppTests, LibraryBackupAppTests): 19 tests pass in 1.5 s

## Phase 5: Polish

- [X] PERF-013-T10 Linux shape: `swift build` of Compositor (FrameTiming) and VisualGenerators with the Linux flags; Diagnostics tests; repo checks (compliance, docs, motion, permission catalog, status events, script tests) — Verified 2026-11-14: macOS host: FrameTimingTests 55 pass (7.6 s), Diagnostics 30 pass (3 s), VisualGenerators builds; touched package code uses only Foundation and Synchronization (no Apple-only API); all six repo checks pass, check_privacy_manifest and check_network_symbols OK. The Linux container run itself is pending CI (no container runtime on this Mac)
- [X] PERF-013-T11 Type-check budget of the touched app files (no function > 300 ms, expression > 150 ms) — Verified 2026-11-14: build with `-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`: no warning in any touched file (the 51 warnings are all pre-existing, in other files)
- [ ] PERF-013-T12 {device} D1: native visual, microphone, overlay on 5 minutes: age line < 100 ms, no drift verdict; export the performance report and check `audioSync` (spec S5)

## Dependencies

T00 → T06-T09; T01 → T06; T02 → T03 → T04, T05; T03 → T06 → T07 → T09; T03 → T08 → T09; T10-T11 after all; T12 last.

## Parallel examples

T04 and T05 (different test files); T08's Diagnostics part alongside T06.

## Implementation strategy

MVP = US2 (estimator + acceptance, T02-T04), then the age meter surface (US1), then polish.
