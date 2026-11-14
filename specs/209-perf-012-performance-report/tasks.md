# Tasks: PERF-012 Diagnostic performance report

**Input**: `specs/209-perf-012-performance-report/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the roadmap acceptance ("Export omits personal media and includes versioned schema") and by
owner rule 7 (short tests, injected values, no wall clock).

## Phase 1: Setup

- [X] PERF-012-T01 Create the feature simulator "PERF12 iPhone 17" (iOS 27.2) and run `xcodegen generate` in the worktree (delete the simulator at the end) — Verified 2026-11-14: simulator D4D0A85B created (`xcrun simctl create`)

## Phase 2: Foundational

- [X] PERF-012-T02 [P] `FrameIntervalHistogram` ("0.1 ms buckets, 2500 buckets, exact max, sum, count, long frames ≥ 25/50/100 ms; percentile = upper edge of the nearest-rank bucket capped by maxMs; nil when count is 0") and `FrameIntervalRecorder` (`Mutex`, never reset) in Packages/Compositor/Sources/FrameTiming/FrameIntervalHistogram.swift — Verified 2026-11-14: FrameIntervalHistogramTests (7 pass)
- [X] PERF-012-T03 `FrameDropCounter.init(intervals:)` records `timestamp − previous` on each accepted `submit` (duplicates ignored as today) in Packages/Compositor/Sources/FrameTiming/FrameDropCounter.swift — Verified 2026-11-14: FrameIntervalHistogramTests.testCounterFeedsTheRecorder; FrameDropCounterTests pass
- [X] PERF-012-T04 [P] Percentile maths and feed tests (known sets: exact p50/p90/p95/p99 within 0.1 ms, max exact, empty → nil, overflow bucket, non-finite ignored, counter feed skips the first and duplicate timestamps; the recorder's bucket storage is allocated once at init, PERF-012-R11) in Packages/Compositor/Tests/FrameTimingTests/FrameIntervalHistogramTests.swift — Verified 2026-11-14: `swift test --package-path Packages/Compositor --filter "FrameIntervalHistogramTests|FrameDropCounterTests"`: 17 tests pass
- [X] PERF-012-T05 [P] `PerformanceReport` model (schemaVersion 1, kind `projectM-iOS.performanceReport`; fixed-set strings map unknown → `unknown`; system strings keep `[A-Za-z0-9 .,_()-]`, at most 40 characters; "timeline ≤ 200") in Packages/Diagnostics/Sources/Diagnostics/PerformanceReport.swift — Verified 2026-11-14: PerformanceReportTests.testSanitising, testTimelineIsCappedAndMarkedTruncated
- [X] PERF-012-T06 `DiagnosticsExporter.performanceReportName(for:)` (`projectM-performance-<UTC yyyyMMdd-HHmmss>.json`) and `encode(_: PerformanceReport)`; `DiagnosticsLog.performanceReport(_:)` signpost event in Packages/Diagnostics/Sources/Diagnostics/DiagnosticsExporter.swift and Logging.swift — Verified 2026-11-14: PerformanceReportTests.testFileNameAndSignpostSummary, testFullReportValidatesAndDeclaresVersionOne
- [X] PERF-012-T07 [P] Report tests: schema validation against the copied contract, `schemaVersion` == 1, absent-not-zero, sanitising, file name, round trip, the signpost summary carries counts only (PERF-012-R10) in Packages/Diagnostics/Tests/DiagnosticsTests/PerformanceReportTests.swift; script test that the schema copy equals the contract in scripts/test_scripts.py — Verified 2026-11-14: `swift test --package-path Packages/Diagnostics`: 29 tests pass (6 PerformanceReportTests cases incl. setup), `python3 scripts/test_scripts.py`: 160 OK

## Phase 3: User Story 1 - Export a performance report (P1) MVP

**Goal**: Settings → Performance → Export performance report shares one privacy-safe JSON file.
**Independent test**: PerformanceReportAppTests (seeded personal media absent, schema valid) and PerformanceReportUITests.

- [ ] PERF-012-T08 [US1] `FrameDropAttachment` owns one `FrameIntervalRecorder` shared by its device and external counters in Apps/projectM-iOS/Coordinators/AppCoordinator+FrameDrops.swift
- [ ] PERF-012-T09 [US1] `PerformanceStateRecorder` (launch uptime, state timeline from `QualityGovernor.changeNotifications`, append only on change, 200 cap + truncated, peak footprint) and memory reading (`task_info` TASK_VM_INFO `phys_footprint`, `os_proc_available_memory`) in Apps/projectM-iOS/Coordinators/PerformanceStateRecorder.swift
- [ ] PERF-012-T10 [US1] `PerformanceReportBuilder` (inputs without any media, name, path, text or address → report) and `AppCoordinator.performanceReportData(exportedAt:)` (visual kind, histogram, PERF-007 counts, PERF-001/002 timings when attached, pool counters, memory) in Apps/projectM-iOS/Coordinators/PerformanceReportBuilder.swift and AppCoordinator+PerformanceReport.swift
- [ ] PERF-012-T11 [US1] `PerformanceReportExport` (REC-012 `ShareFileStore` copy, share kind `performanceReport`, notice on failure, DEBUG `-uitestShareSimulation`) in Apps/projectM-iOS/Coordinators/PerformanceReportExport.swift and CaptureShareCoordinator.swift
- [ ] PERF-012-T12 [US1] `PerformanceReportSection` (button `performanceReport.export`, footer, notice, simulation buttons, `ActivitySharePresenter`) in Apps/projectM-iOS/Views/PerformanceReportSection.swift; wired from SettingsView.performanceSection and VisualizerView
- [ ] PERF-012-T13 [US1] Acceptance test: a session seeded with a photo, a text overlay message, a user preset name, a scene name, a recording file name and an OSC peer; the JSON holds none of them or their paths, every string is a schema enum/const value or system metadata, `schemaVersion` == 1 and the JSON validates against the contract, in Apps/projectM-iOS/Tests/PerformanceReportAppTests.swift
- [ ] PERF-012-T14 [US1] UI test: Settings → Performance → Export → simulated share completed → "Shared.", sharing copy removed (under 30 s) in Apps/projectM-iOS/UITests/PerformanceReportUITests.swift

## Phase 4: User Story 2 - Report without frame data (P2)

- [ ] PERF-012-T15 [US2] Test: no frame measured → `sampleCount` 0, no percentile keys, file valid (in PerformanceReportAppTests.swift)

## Phase 5: Polish

- [ ] PERF-012-T16 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbol checks on the Debug app, type-check budget, `LibraryBackupAppTests` (no new key, PERF-012-R11), PosterBoard counts
- [ ] PERF-012-T17 {device} D1: export after a 1-minute session with the overlay shown; the file validates and shows plausible percentiles and counters (PERF-012-S5)

## Dependencies

T02 → T03 → T08; T05 → T06 → T10; T09, T10, T11 → T12 → T13, T14, T15; T16 last; T17 needs a person and D1.
Parallel: T02/T04 with T05/T07.

## Implementation strategy

MVP = Phases 2-3 (US1); US2 is a test of the same code path.

## Analysis (speckit-analyze, 2026-11-14)

- C1 (medium): PERF-012-R10 had no test → T07 now tests the signpost summary.
- C2 (medium): PERF-012-R11 had no task → T04 (no per-frame allocation) and T16 (no stored key).
- F1 (low): "longer than" vs "≥" thresholds → the spec now says "at least".
- Coverage: R1 T12, T14; R2 T06, T11, T14; R3 T05, T07; R4 T05, T10; R5 T02-T04, T10; R6 T10; R7 T09; R8 T09, T10; R9 T05, T13; R10 T06, T07; R11 T03, T04, T16; S1 T13; S2 T07, T13; S3 T04; S4 T14; S5 T17. No constitution conflict.
