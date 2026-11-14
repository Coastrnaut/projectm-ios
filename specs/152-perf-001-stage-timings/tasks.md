# Tasks: PERF-001 Per-stage frame timings

**Input**: `specs/152-perf-001-stage-timings/` (plan.md, spec.md, research.md, data-model.md,
contracts/frame-stage-timer.md, quickstart.md)

**Tests**: requested by the brief (acceptance, ring, percentiles, rejection, encode, GPU integration,
export round trip, UI test, Linux).

Format: `- [ ] PERF-001-Tnn [P?] [US?] description (file)`.

## Phase 1: Setup

- [X] PERF-001-T01 Add target `FrameTiming` (no dependencies) to the `Compositor` library product and a `FrameTimingTests` test target in `Packages/Compositor/Package.swift`; add `FrameTiming` to `CompositorTests` and `ANGLERendering` dependencies. — Verified 2026-11-14: `swift build`/`swift test` of the Compositor package (all 10 test bundles pass); the app links FrameTiming through the Compositor product

## Phase 2: Foundational (the pure timer, Linux-tested)

- [X] PERF-001-T02 `FrameStage` (labels `audio`, `render`, `composite`, `output`, `encode`, `present`; `encode` conditional) in `Packages/Compositor/Sources/FrameTiming/FrameStage.swift`. — Verified 2026-11-14: FrameStageTimerTests (label assertions)
- [X] PERF-001-T03 `FrameStageTimer` per contract C1 (ring of 120 frames, preallocated, injected `() -> UInt64` ns clock, rejection of "NaN, ±∞, negative, end before begin", no allocation on begin/end/record/endFrame) and `FrameStageReport`/`StageStatistic` per C2-C3 in `Packages/Compositor/Sources/FrameTiming/FrameStageTimer.swift` and `FrameStageReport.swift`. — Verified 2026-11-14: FrameStageTimerTests 13 tests pass (0.005 s host; also with -DCOMPOSITOR_NO_METAL, the Linux shape); allocation-free frame path by design review (preallocated arrays, in-place writes)
- [X] PERF-001-T04 [P] `MetalGPUFrameTimes` per C5 (4 slots, polls `.completed`, rejects start ≤ 0) under `#if canImport(Metal) && !COMPOSITOR_NO_METAL` in `Packages/Compositor/Sources/FrameTiming/MetalGPUFrameTimes.swift`. — Verified 2026-11-14: CompositorStageTimingTests (frame GPU measured on the Mac Studio GPU: median 0.30 ms)
- [X] PERF-001-T05 Tests in `Packages/Compositor/Tests/FrameTimingTests/FrameStageTimerTests.swift`: acceptance (synthetic frame 2/3/4/5/6 ms → exact labels, exact finite values, GPU unavailable); ring wraparound; median/p95; NaN/negative/backwards clock rejected; encode only while recording; a stage begun but not ended records nothing; window clears on configure; overlay lines; on-demand bench (`PERF001_BENCH=1`) of the cost per frame. — Verified 2026-11-14: `swift test --filter FrameTimingTests` 13 passed + 1 on-demand bench skipped; bench release build 0.31-0.61 µs per 6-stage frame, Debug 2.46 µs

## Phase 3: User Story 1 — see where a frame's time goes (P1)

**Independent test**: T05 acceptance + T07 GPU integration + T12 UI test.

- [X] PERF-001-T06 [US1] Compositor split per C4: `stageClock`, `lastOutputPassStartNanoseconds` stamped before the flash guard in `Packages/Compositor/Sources/Compositor/Compositor.swift`. — Verified 2026-11-14: CompositorStageTimingTests.testWithoutStageClockNothingIsStamped and the mark-inside-call assertions
- [X] PERF-001-T07 [US1] GPU integration test on the Mac: a real composite into an offscreen target, timed through the split and the poller; composite, output and frame GPU finite and ≥ 0 (`Packages/Compositor/Tests/CompositorTests/CompositorStageTimingTests.swift`). — Verified 2026-11-14: CompositorStageTimingTests 2 passed (0.07 s): composite 0.09/1.04, output 0.03/0.21, present 0.01/0.05, frame GPU 0.30/4.32 ms (Mac, not device evidence)
- [X] PERF-001-T08 [US1] projectM stages (audio, render, output, present) in `ANGLERenderer.renderFrame` behind `stageTimer` (`Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift`). — Verified 2026-11-14: app build; RenderFaultUITests (projectM with the overlay, so the timer, on) 2 passed
- [X] PERF-001-T09 [US1] Native and compositor host stages (`Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift`, `CameraVisualHost.swift`, `PhotoVisualHost.swift`, `VideoVisualHost.swift`, `TextVisualHost.swift`): `stageTimer` property, brackets, frame GPU poller, encode only while recording; shared helper in `Apps/projectM-iOS/Visuals/FrameStageTiming.swift`. — Verified 2026-11-14: app build; FrameStageAppTests (native and photo hosts) and FrameStageOverlayUITests; RenderFaultUITests on Photo
- [X] PERF-001-T10 [US1] Attach/detach on overlay and visual change in `Apps/projectM-iOS/Coordinators/AppCoordinator+FrameStages.swift`; overlay stage lines in `Apps/projectM-iOS/Views/PerformanceOverlay.swift` and `VisualizerView.swift`. — Verified 2026-11-14: FrameStageAppTests.testTimerFollowsTheShownVisualAndStopsWithTheOverlay; FrameStageOverlayUITests
- [X] PERF-001-T11 [US1] App unit tests (`Apps/projectM-iOS/Tests/FrameStageAppTests.swift`): pipelines per visual, overlay lines, export conversion, and overlay off → no visual holds a timer (PERF-001-R8, S5 "nothing with the overlay off"). — Verified 2026-11-14: FrameStageAppTests 6 passed (1.8 s) on "PERF1 iPhone 17" iOS 27.2
- [X] PERF-001-T12 [US1] UI test under 30 s (`Apps/projectM-iOS/UITests/FrameStageOverlayUITests.swift`): overlay on, native visual, the overlay shows "stages ms" and the labels audio, render, present. — Verified 2026-11-14: FrameStageOverlayUITests 1 passed (13.4 s) on "PERF1 iPhone 17" iOS 27.2

## Phase 4: User Story 2 — take the numbers away (P2)

- [X] PERF-001-T13 [P] [US2] `DiagnosticsSnapshot.frameTimings` (optional; "GPU and CPU keys absent when unavailable; at most 6 stages"), text lines, schema property in both copies (`Packages/Diagnostics/...`, `specs/001-ios-projectm-visualizer/contracts/diagnostics-export.schema.json`). — Verified 2026-11-14: Diagnostics `swift test` 16 passed; schema copies identical (test_scripts 153 OK)
- [X] PERF-001-T14 [US2] Round trip and schema tests, absent key when nil (`Packages/Diagnostics/Tests/DiagnosticsTests/FrameTimingsExportTests.swift`). — Verified 2026-11-14: FrameTimingsExportTests 4 passed (0.01 s)
- [X] PERF-001-T15 [US2] Automation mode `perf001` writes the report in diagnostics format plus fps with the timer off and on (`Apps/projectM-iOS/Automation/AutomationRunner.swift`). — Verified 2026-11-14: app build (Debug, automation compiled in); device run is T16
- [ ] PERF-001-T16 [US2] {device} Run `perf001` on D1 and record per-stage numbers and the overhead in `docs/test-reports/performance.md`.

## Phase 5: Polish

- [X] PERF-001-T17 Repo checks, type-check budget, Linux shape (`swift test` with `-DCOMPOSITOR_NO_METAL` for FrameTiming), privacy manifest and network symbol checks; spec status and research measurements. — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 OK; check_privacy_manifest OK; check_network_symbols OK; type-check budget: no new warnings over budget in touched code (VisualizerView `layers` 335-396 ms is pre-existing in other worktrees too and was reduced by moving the overlay out)

## Dependencies

T01 → T02-T04 → T05; T06 → T07; T03 → T08, T09 → T10 → T11, T12; T13 → T14 → T15 → T16. US2's T13-T14
are independent of US1.

## Parallel examples

T04 with T03; T13-T14 with T06-T12.

## Implementation strategy

MVP = Phase 2 + T05 (the roadmap acceptance), then the app wiring, then export.
