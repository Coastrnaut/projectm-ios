# Tasks: PERF-002 GPU budget meter

**Input**: `specs/160-perf-002-gpu-budget/` (plan.md, spec.md, research.md, data-model.md,
contracts/frame-budget-meter.md, quickstart.md)

**Tests**: requested by the brief (acceptance, render-path spy, deadlines, unavailable passes, hysteresis,
overlay text, UI test, Linux shape).

Format: `- [ ] PERF-002-Tnn [P?] [US?] description (file)`.

## Phase 1: Setup

- [ ] PERF-002-T01 Confirm no package change is needed: the meter goes in the existing `FrameTiming` target (Foundation only) and its tests in `FrameTimingTests` (`Packages/Compositor/Package.swift` unchanged).

## Phase 2: Foundational (the pure meter, Linux-tested)

- [ ] PERF-002-T02 `FrameDeadline` per contract C1 ("min of the valid (finite, > 0) inputs, else 60"; `periodMs = 1000 / framesPerSecond`) and `FrameBudgetPolicy` (threshold 0.80 clamped to "(0, 1]", clear 0.70 clamped to "(0, thresholdShare]", minimumSamples 30 "≥ 1") in `Packages/Compositor/Sources/FrameTiming/FrameBudget.swift`.
- [ ] PERF-002-T03 `BudgetPass`, `PassStatus`, `FrameBudgetVerdict` (passes in frame order, cpu/gpu estimates, flagged, overlay lines per C3) and `FrameBudgetMeter` (13-bit flag mask; transitions per data-model.md: "unavailable → clear; samples < minimum → unchanged; p95 > threshold → set; p95 < clear → clear") in `Packages/Compositor/Sources/FrameTiming/FrameBudget.swift`.
- [ ] PERF-002-T04 Tests in `Packages/Compositor/Tests/FrameTimingTests/FrameBudgetTests.swift`: acceptance (composite p95 over threshold, others under → flagged == [composite cpu]); render-path spy (600 frames through a timer with a spy renderer, meter evaluated every 60 frames, slow vs fast: equal frame and draw counts, no draw skipped); deadlines 60/120/30 fps and fallbacks; unavailable GPU never flagged; hysteresis (stays between clear and threshold, clears below clear); minimum samples; policy clamping; overlay lines; equal to threshold not flagged.

## Phase 3: User Story 1 — see which pass blows the frame budget (P1)

**Independent test**: T04 acceptance and spy, T08 app tests, T09 UI test.

- [ ] PERF-002-T05 [US1] Meter in `FrameStageAttachment` (reset when the timer moves to another visual or stops), deadline from `UIScreen.maximumFramesPerSecond` and `QualityGovernor.current().maxFramesPerSecond`, verdict lines appended to `frameStageLines()`, DEBUG `-uitestSlowStage <stage>:<ms>` report injection per C5, in `Apps/projectM-iOS/Coordinators/AppCoordinator+FrameStages.swift`.
- [ ] PERF-002-T06 [US1] Overlay highlights lines starting with `over budget:` (colour plus text; still inside the combined accessibility label; no announcement) in `Apps/projectM-iOS/Views/PerformanceOverlay.swift`.
- [ ] PERF-002-T07 [P] [US1] Simulator "PERF2" created per AGENT_RULES; app build for testing with the type-check budget flags.
- [ ] PERF-002-T08 [US1] App tests in `Apps/projectM-iOS/Tests/FrameBudgetAppTests.swift`: injection parsing (valid, unknown stage, bad ms), injection replaces only the named stage's CPU figure, attachment resets the meter on a visual change and overlay off, the visual sees only `stageTimer` assignments (spy) while flags are raised.
- [ ] PERF-002-T09 [US1] UI test `Apps/projectM-iOS/UITests/FrameBudgetOverlayUITests.swift` (< 30 s): circular spectrum, overlay on, `-uitestSlowStage render:40` → overlay label contains `budget ` and `over budget: render cpu 40.00 ms > `.

## Phase 4: User Story 2 — take the verdict away (P2)

- [ ] PERF-002-T10 [P] [US2] `DiagnosticsSnapshot.FrameTimings.Budget` (optional; `flaggedPasses` ≤ 13 labels; non-finite or negative values absent) and text lines in `Packages/Diagnostics/Sources/Diagnostics/DiagnosticsSnapshot.swift` and `DiagnosticsExporter.swift`; schema `frameTimings.budget` in `specs/001-ios-projectm-visualizer/contracts/diagnostics-export.schema.json` and the test copy; tests in `Packages/Diagnostics/Tests/DiagnosticsTests/FrameTimingsExportTests.swift` (round trip, schema-valid, absent when nil).
- [ ] PERF-002-T11 [US2] `AppCoordinator.exportTimings(_:budget:)` conversion and the automation `perf001` mode writing the verdict (`Apps/projectM-iOS/Coordinators/AppCoordinator+FrameStages.swift`, `Apps/projectM-iOS/Automation/AutomationRunner.swift`).

## Phase 5: Polish

- [ ] PERF-002-T12 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbol checks on the Debug app, PosterBoard counts; delete simulator and derived data; spec status updated.
- [ ] PERF-002-T13 {device} On D1, the `perf001` automation run's `frameTimings.budget` at normal load (quickstart C). Pending device.

## Dependencies

T01 → T02 → T03 → T04; T05-T06 need T03; T08-T09 need T05-T07; T10 independent of US1 (parallel);
T11 needs T03 and T10; T12 last.

## Parallel examples

- T10 (Diagnostics) alongside T05-T06 (app).
- T07 (simulator creation, build) while T04 runs on the host.

## Implementation strategy

MVP = Phase 2 + US1 (the meter and the overlay flag, the roadmap acceptance). US2 adds the export.
