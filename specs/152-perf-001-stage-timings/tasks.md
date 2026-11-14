# Tasks: PERF-001 Per-stage frame timings

**Input**: `specs/152-perf-001-stage-timings/` (plan.md, spec.md, research.md, data-model.md,
contracts/frame-stage-timer.md, quickstart.md)

**Tests**: requested by the brief (acceptance, ring, percentiles, rejection, encode, GPU integration,
export round trip, UI test, Linux).

Format: `- [ ] PERF-001-Tnn [P?] [US?] description (file)`.

## Phase 1: Setup

- [ ] PERF-001-T01 Add target `FrameTiming` (no dependencies) to the `Compositor` library product and a `FrameTimingTests` test target in `Packages/Compositor/Package.swift`; add `FrameTiming` to `CompositorTests` and `ANGLERendering` dependencies.

## Phase 2: Foundational (the pure timer, Linux-tested)

- [ ] PERF-001-T02 `FrameStage` (labels `audio`, `render`, `composite`, `output`, `encode`, `present`; `encode` conditional) in `Packages/Compositor/Sources/FrameTiming/FrameStage.swift`.
- [ ] PERF-001-T03 `FrameStageTimer` per contract C1 (ring of 120 frames, preallocated, injected `() -> UInt64` ns clock, rejection of "NaN, ±∞, negative, end before begin", no allocation on begin/end/record/endFrame) and `FrameStageReport`/`StageStatistic` per C2-C3 in `Packages/Compositor/Sources/FrameTiming/FrameStageTimer.swift` and `FrameStageReport.swift`.
- [ ] PERF-001-T04 [P] `MetalGPUFrameTimes` per C5 (4 slots, polls `.completed`, rejects start ≤ 0) under `#if canImport(Metal) && !COMPOSITOR_NO_METAL` in `Packages/Compositor/Sources/FrameTiming/MetalGPUFrameTimes.swift`.
- [ ] PERF-001-T05 Tests in `Packages/Compositor/Tests/FrameTimingTests/FrameStageTimerTests.swift`: acceptance (synthetic frame 2/3/4/5/6 ms → exact labels, exact finite values, GPU unavailable); ring wraparound; median/p95; NaN/negative/backwards clock rejected; encode only while recording; a stage begun but not ended records nothing; window clears on configure; overlay lines; on-demand bench (`PERF001_BENCH=1`) of the cost per frame.

## Phase 3: User Story 1 — see where a frame's time goes (P1)

**Independent test**: T05 acceptance + T07 GPU integration + T12 UI test.

- [ ] PERF-001-T06 [US1] Compositor split per C4: `stageClock`, `lastOutputPassStartNanoseconds` stamped before the flash guard in `Packages/Compositor/Sources/Compositor/Compositor.swift`.
- [ ] PERF-001-T07 [US1] GPU integration test on the Mac: a real composite into an offscreen target, timed through the split and the poller; composite, output and frame GPU finite and ≥ 0 (`Packages/Compositor/Tests/CompositorTests/CompositorStageTimingTests.swift`).
- [ ] PERF-001-T08 [US1] projectM stages (audio, render, output, present) in `ANGLERenderer.renderFrame` behind `stageTimer` (`Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift`).
- [ ] PERF-001-T09 [US1] Native and compositor host stages (`Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift`, `CameraVisualHost.swift`, `PhotoVisualHost.swift`, `VideoVisualHost.swift`, `TextVisualHost.swift`): `stageTimer` property, brackets, frame GPU poller, encode only while recording; shared helper in `Apps/projectM-iOS/Visuals/FrameStageTiming.swift`.
- [ ] PERF-001-T10 [US1] Attach/detach on overlay and visual change in `Apps/projectM-iOS/Coordinators/AppCoordinator+FrameStages.swift`; overlay stage lines in `Apps/projectM-iOS/Views/PerformanceOverlay.swift` and `VisualizerView.swift`.
- [ ] PERF-001-T11 [US1] App unit tests (`Apps/projectM-iOS/Tests/FrameStageAppTests.swift`): pipelines per visual, overlay lines, export conversion, and overlay off → no visual holds a timer (PERF-001-R8, S5 "nothing with the overlay off").
- [ ] PERF-001-T12 [US1] UI test under 30 s (`Apps/projectM-iOS/UITests/FrameStageOverlayUITests.swift`): overlay on, native visual, the overlay shows "stages ms" and the labels audio, render, present.

## Phase 4: User Story 2 — take the numbers away (P2)

- [ ] PERF-001-T13 [P] [US2] `DiagnosticsSnapshot.frameTimings` (optional; "GPU and CPU keys absent when unavailable; at most 6 stages"), text lines, schema property in both copies (`Packages/Diagnostics/...`, `specs/001-ios-projectm-visualizer/contracts/diagnostics-export.schema.json`).
- [ ] PERF-001-T14 [US2] Round trip and schema tests, absent key when nil (`Packages/Diagnostics/Tests/DiagnosticsTests/FrameTimingsExportTests.swift`).
- [ ] PERF-001-T15 [US2] Automation mode `perf001` writes the report in diagnostics format plus fps with the timer off and on (`Apps/projectM-iOS/Automation/AutomationRunner.swift`).
- [ ] PERF-001-T16 [US2] {device} Run `perf001` on D1 and record per-stage numbers and the overhead in `docs/test-reports/performance.md`.

## Phase 5: Polish

- [ ] PERF-001-T17 Repo checks, type-check budget, Linux shape (`swift test` with `-DCOMPOSITOR_NO_METAL` for FrameTiming), privacy manifest and network symbol checks; spec status and research measurements.

## Dependencies

T01 → T02-T04 → T05; T06 → T07; T03 → T08, T09 → T10 → T11, T12; T13 → T14 → T15 → T16. US2's T13-T14
are independent of US1.

## Parallel examples

T04 with T03; T13-T14 with T06-T12.

## Implementation strategy

MVP = Phase 2 + T05 (the roadmap acceptance), then the app wiring, then export.
