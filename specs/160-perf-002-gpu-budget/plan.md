# Implementation Plan: PERF-002 GPU budget meter

**Branch**: `feature/perf-002` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/160-perf-002-gpu-budget/spec.md`

## Summary

Three pure-Swift types join PERF-001's `FrameTiming` target (Compositor package, Foundation only,
Linux-tested):

- `FrameDeadline`: the target frame rate (the lower of the display's maximum and the visual's cap, 60 fps
  fallback) and its period in ms.
- `FrameBudgetPolicy`: threshold share (0.80), clear share (0.70) and minimum samples (30), clamped.
- `FrameBudgetMeter`: reads a `FrameStageReport` and a deadline and returns a `FrameBudgetVerdict`
  (per-pass status, cpu and gpu estimates, flagged passes, overlay lines). Its only state is a 13-bit flag
  mask for hysteresis. It never sees a renderer or the timer: it is called once a second with the overlay,
  off the frame path, so it cannot block or alter rendering.

The app keeps one meter in `FrameStageAttachment` (reset on a visual change or overlay off), computes the
deadline from `UIScreen.maximumFramesPerSecond` and `QualityGovernor.current().maxFramesPerSecond`, and
appends the verdict's lines to the overlay's stage lines. The overlay draws lines starting with
"over budget:" in a highlight colour; the text stays in the combined accessibility label, no announcement.
A DEBUG launch argument (`-uitestSlowStage <stage>:<ms>`) replaces one stage's CPU figure in the report (never
the render path) so the UI test can show a flag. Diagnostics gains an optional `budget` object inside
`frameTimings`; the automation `perf001` mode writes it.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26 and Linux)
**Primary Dependencies**: Foundation; UIKit (screen max fps) and Rendering (`QualityGovernor`) in the app only
**Storage**: none (no new UserDefaults key; launch argument read from `ProcessInfo.arguments` in DEBUG)
**Testing**: XCTest: FrameTimingTests (host + Linux shape), Diagnostics round trip and schema, app unit
tests (overlay lines, attachment reset, injection parse), one UI test (< 30 s)
**Target Platform**: iOS/iPadOS 26+, macOS host tests, Linux for the pure target
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: zero added frame-path work; one evaluation per second (≤ 13 passes)
**Constraints**: purely observational (R6); no allocation on the frame path (R7); public APIs only
**Scale/Scope**: 6 stages × 2 domains + frame GPU = 13 passes

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs | Pass: `UIScreen.maximumFramesPerSecond`, `ProcessInfo`; no counters or private API. |
| VI Modular boundaries | Pass: the meter knows only the report; Diagnostics gets a plain Codable value; the app converts. |
| VII Real-time audio safety | Pass: nothing on audio threads or the frame path. |
| X Evidence-based quality | Pass: deterministic unit tests with injected reports; simulator UI test checks text only; device numbers are a `{device}` task. |
| Privacy | Pass: metadata only (stage names, ms, shares); no new keys; nothing leaves the device by itself. |

No violations; no ADR needed (no default overridden; the overlay was already opt-in).

## Project Structure

### Documentation (this feature)

```text
specs/160-perf-002-gpu-budget/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/frame-budget-meter.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/FrameTiming/FrameBudget.swift      # deadline, policy, pass, verdict, meter
Packages/Compositor/Tests/FrameTimingTests/FrameBudgetTests.swift   # acceptance, spy, deadlines, hysteresis, lines
Packages/Diagnostics/
├── Sources/Diagnostics/DiagnosticsSnapshot.swift   # + FrameTimings.Budget (optional)
├── Sources/Diagnostics/DiagnosticsExporter.swift   # + budget text lines
└── Tests/DiagnosticsTests/FrameTimingsExportTests.swift (+ schema copy)
specs/001-ios-projectm-visualizer/contracts/diagnostics-export.schema.json   # + frameTimings.budget
Apps/projectM-iOS/
├── Coordinators/AppCoordinator+FrameStages.swift   # meter in the attachment, deadline, lines, export, DEBUG injection
├── Views/PerformanceOverlay.swift                  # highlight "over budget:" lines
├── Automation/AutomationRunner.swift               # perf001 writes the budget verdict
├── Tests/FrameBudgetAppTests.swift
└── UITests/FrameBudgetOverlayUITests.swift
```

**Structure Decision**: The meter lives beside the timer because it consumes only `FrameStageReport` and must
stay Linux-testable. `AppCoordinator.swift`, `VisualizerView.swift` and `Compositor.swift` are not touched:
the overlay's existing `stageLines` closure carries the budget lines.

## Complexity Tracking

None.
