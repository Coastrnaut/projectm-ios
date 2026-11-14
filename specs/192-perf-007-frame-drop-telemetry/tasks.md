# Tasks: PERF-007 Frame drop telemetry

**Input**: Design documents from `specs/192-perf-007-frame-drop-telemetry/`
**Tests**: requested by the brief (acceptance, session reset, per-output separation, unavailable, Linux shape, app test with an injected clock, export round trip).

## Phase 1: Setup

- [X] PERF-007-T01 Confirm the baseline: `swift test --package-path Packages/Compositor --filter FrameTimingTests` passes before changes; `Build` symlink present; simulator "PERF7 iPhone 17" (iOS 27.2) created — Verified 2026-11-14: `swift test --package-path Packages/Compositor --filter FrameBudgetTests` passed before changes; Build symlink present; simulator "PERF7 iPhone 17" (iOS 27.2) created

## Phase 2: Foundational (the counter)

- [X] PERF-007-T02 `FrameDropOutput`, `FrameDropSession`, `FrameDropTicket`, `FrameDropCounts` (with `recording(written:droppedSlots:)` and `line(for:)`) and the lock-free `FrameDropCounter` (contract C1) in Packages/Compositor/Sources/FrameTiming/FrameDropCounter.swift — Verified 2026-11-14: FrameDropCounterTests (10 tests, host, 15 s run incl. build check); `swift build --target FrameTiming -Xswiftc -DCOMPOSITOR_NO_METAL` OK

## Phase 3: User Story 2 - Reset per session, never double-count (P1)

- [X] PERF-007-T03 [US2] Acceptance tests in Packages/Compositor/Tests/FrameTimingTests/FrameDropCounterTests.swift: injected sequence → exact counts; duplicated presented reports and repeated timestamps counted once; out-of-order within the window counted once; session reset zeroes; late reports of the previous session excluded (stale); concurrent duplicate reports from several threads counted once — Verified 2026-11-14: FrameDropCounterTests.testInjectedSequenceGivesExactCountsAndDuplicatesCountOnce, testOutOfOrderReportsWithinTheWindowCountOnce, testConcurrentDuplicateReportsCountOnce, testANewSessionZeroesEveryCountAndIgnoresTheOldSessionsLateReports, testAReportForAFrameNeverSubmittedIsStale (host)
- [X] PERF-007-T04 [P] [US2] Separation and unavailable tests: two counters (device, external) never affect each other; a session without presentation reports nil presented/late/discarded and the line reads "unavailable"; recording counts from written and dropped slots — Verified 2026-11-14: FrameDropCounterTests.testOutputsNeverAffectEachOther, testAPathWithoutPresentationReportsUnavailable, testRecordingCountsAndLine, testAnInvalidIntervalInfersNoSlotsAndNoLateness (host)

## Phase 4: User Story 1 - Counts per output in the overlay (P1)

- [X] PERF-007-T05 [US1] `FrameDropCounted` protocol and `track(_:link:)` drawable helper in Apps/projectM-iOS/Visuals/FrameDropCounting.swift; a `frameDrops` property and one call before `present` in the native spectrum, Camera, Photo, Video and Text hosts; `ANGLERenderer.frameDrops` (submit only) in Packages/ANGLERendering — Verified 2026-11-14: app build-for-testing on PERF7 and unsigned generic-iOS device build succeed with no warnings in changed files (type-check flags on); the presented handler compiles for devices only (the simulator SDK lacks it, research PERF-007-D1)
- [X] PERF-007-T06 [US1] `FrameDropAttachment` (device and external counters, session on attach, visual change, output change, overlay on) and `frameDropLines()` in Apps/projectM-iOS/Coordinators/AppCoordinator+FrameDrops.swift; lines appended in `frameStageLines()`, stop with `stopFrameStageTiming()`; recording line from `VideoRecordingCoordinator.currentStatistics` — Verified 2026-11-14: FrameDropAppTests.testSessionsFollowTheVisualTheDisplayAndTheOverlay, testTheExternalDisplayReportsEveryOutputChange, testRecordingLineLiveThenFinishedOnlyWithinTheCountingSession on PERF7
- [X] PERF-007-T07 [US1] Overlay: lines starting with "frames " in their own text (`overlayFrameDrops`) in Apps/projectM-iOS/Views/PerformanceOverlay.swift — Verified 2026-11-14: FrameDropAppTests.testOverlaySeparatesTheFramesLines; FrameDropOverlayUITests.testOverlayShowsTheDeviceFramesLine (12.5 s) on PERF7; FrameStageOverlayUITests still passes (9.2 s)
- [X] PERF-007-T08 [US1] App tests in Apps/projectM-iOS/Tests/FrameDropAppTests.swift: device counter driven with an injected clock (submit/presented events) gives exact counts; the attachment starts a new session on visual or output change and attaches the external counter when the visual is external; overlay split keeps "frames" lines apart — Verified 2026-11-14: FrameDropAppTests (6 tests) on PERF7 with FrameStageAppTests, FrameBudgetAppTests, ExternalDisplayCoordinatorTests, HotPlugAcceptanceTests: 33 tests, 0 failures, 3.7 s

## Phase 5: User Story 3 - Export (P2)

- [X] PERF-007-T09 [P] [US3] `DiagnosticsSnapshot.FrameDrops` (optional top-level `frameDrops`) in Packages/Diagnostics/Sources/Diagnostics/DiagnosticsSnapshot.swift; schema in specs/001-ios-projectm-visualizer/contracts/diagnostics-export.schema.json and the test resource copy — Verified 2026-11-14: Diagnostics package 24 tests pass on the host (14.5 s incl. build); both schema copies identical
- [X] PERF-007-T10 [US3] Round-trip and schema tests in Packages/Diagnostics/Tests/DiagnosticsTests/FrameDropsExportTests.swift; `AppCoordinator.exportFrameDrops`; automation perf001 adds `frameDrops` — Verified 2026-11-14: FrameDropsExportTests (3 tests, host); FrameDropAppTests.testMetalPathsMeasurePresentationAndExportConversion on PERF7; AutomationRunner perf001 compiles (app build)

## Phase 6: Polish

- [X] PERF-007-T11 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), Linux shape (`swift build` of FrameTiming with no Apple-only API), type-check budget, privacy manifest and network symbols on the Debug app; PosterBoard counts — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events exit 0; test_scripts 159 tests OK; check_privacy_manifest OK and check_network_symbols OK (19 images) on the Debug simulator app; no type-check warnings in changed files; PosterBoard reports 25 before and 25 after; Linux shape: FrameTiming and Diagnostics use only Swift, Foundation and Synchronization (built here with -DCOMPOSITOR_NO_METAL; not run on a Linux host, pending CI)
- [ ] PERF-007-T12 {device} On D1 with an external display: overlay shows `frames external` counting after the connection settles, the device counter stops; a recording line matches the recording's dropped slots

## Dependencies

T02 → T03, T04 → T05 → T06 → T07, T08. T09 → T10. T11 last.

## Implementation strategy

Counter and its tests first (the acceptance), then the app wiring, then the export.

## Analysis (speckit-analyze, 2026-11-14)

- Coverage: R1-R3 → T02-T04; R4, R5 → T03; R6 → T06, T08; R7 → T04, T07, T10; R8 → T02 (atomic cells, no lock); R9 → T02, T11; R10 → T06, T07; R11 → T09, T10; R12, R13 → T11 (network symbols, no stored key). S1-S5 → T03, T03, T04, T04/T07, T10.
- Fix applied: the spec's unavailable rule (R7) now names the simulator's Metal paths, found during implementation (research PERF-007-D1).
- Fix applied: T07 gained a UI test (`FrameDropOverlayUITests`) to show the line end to end; under the 30 s budget.
- No terminology drift: "submitted, skipped, presented, late, discarded, stale" in spec, contract, code and tests.
