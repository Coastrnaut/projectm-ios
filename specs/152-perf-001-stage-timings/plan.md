# Implementation Plan: PERF-001 Per-stage frame timings

**Branch**: `feature/perf-001` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/152-perf-001-stage-timings/spec.md`

## Summary

A pure-Swift `FrameStageTimer` (new target `FrameTiming` in the Compositor package, Foundation only,
Linux-tested) records CPU time per labelled stage from an injected monotonic clock into a fixed ring of
120 frames, plus optional GPU times, and reports per-stage median and p95 with explicit "unavailable"
values. A Metal helper in the same target (`MetalGPUFrameTimes`, compiled only where Metal exists) polls
committed command buffers for `gpuStartTime`/`gpuEndTime` on the frame thread, with no completion
handler, no allocation and no lock.

Every visual's frame loop brackets its stages only while a timer is attached (`stageTimer != nil`):

- projectM (`ANGLERenderer.renderFrame`): audio (PCM read + feed), render (engine render), output (FX-019
  flash-limiter pass), present (`eglSwapBuffers`). GPU unavailable (ANGLE submits its own Metal work).
- Native spectrum/oscilloscope (`NativeSpectrumHost.frame`): audio (analysis read, smoothing,
  modulation), render (generator, glow chain), encode (REC-003 copy, only while recording), present
  (present + commit). Frame GPU from its command buffer.
- Compositor visuals (camera, photo, video, text hosts): audio (analysis read), composite and output
  (split by the compositor's new optional `stageClock` mark at the start of the flash guard / output
  pass), encode, present. Frame GPU from the command buffer.

The app attaches one shared timer to the shown visual while the performance overlay is shown
(`AppCoordinator+FrameStages.swift`), restarting the window on a visual change and detaching on
overlay off. The overlay (FR-048) shows the stage lines. Diagnostics gains an optional
`frameTimings` section (`DiagnosticsSnapshot.FrameTimings`, schema property, text lines); the
automation runner's new `perf001` mode writes it for device runs.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26 and Linux swift:6.4.2)
**Primary Dependencies**: Foundation, Dispatch (clock), Metal (GPU times, Apple only), SwiftUI (overlay)
**Storage**: none (in-memory ring; automation JSON in Documents only in device runs)
**Testing**: XCTest: FrameTiming unit tests (host + Linux), Compositor GPU integration test (Mac GPU),
Diagnostics round trip, app unit tests (overlay lines, coordinator attach), one UI test (< 30 s)
**Target Platform**: iOS/iPadOS 26+, macOS host tests, Linux for the pure target
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: < 1 µs CPU per frame of six stages with the timer on; zero work off
**Constraints**: no allocation or lock on the frame path; never called from an audio callback (T063);
public APIs only; no new UserDefaults keys
**Scale/Scope**: 6 stages × 120 frames ring; 6 frame loops instrumented

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs | Pass: `MTLCommandBuffer.gpuStartTime/gpuEndTime/status`, `DispatchTime`. |
| VI Modular boundaries | Pass: the timer knows no renderer; renderers get an optional timer; the compositor exposes one optional clock mark; Diagnostics stays independent (the app converts the report). |
| VII Real-time audio safety | Pass: the timer runs on the frame (main) thread only; nothing in audio callbacks; preallocated ring; no locks. |
| X Evidence-based quality | Pass: unit tests for the deterministic timer; GPU integration test on the Mac; device numbers are a `{device}` task, simulator never evidence. |
| Privacy | Pass: metadata only (labels, counts, ms); no new keys; nothing leaves the device by itself. |

No violations; no ADR needed (no default overridden).

## Project Structure

### Documentation (this feature)

```text
specs/152-perf-001-stage-timings/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/frame-stage-timer.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/
├── Package.swift                                   # + target FrameTiming (in product Compositor), + FrameTimingTests
├── Sources/FrameTiming/FrameStage.swift            # stage enum, labels
├── Sources/FrameTiming/FrameStageTimer.swift       # ring, begin/end, record, report
├── Sources/FrameTiming/FrameStageReport.swift      # report, statistic, overlay lines
├── Sources/FrameTiming/MetalGPUFrameTimes.swift    # command-buffer GPU poller (#if canImport(Metal))
├── Sources/Compositor/Compositor.swift             # + stageClock, lastOutputPassStartNanoseconds
├── Tests/FrameTimingTests/                         # acceptance, ring, percentiles, rejection, encode, bench
└── Tests/CompositorTests/CompositorStageTimingTests.swift   # GPU integration
Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift   # + stageTimer, stage brackets
Packages/Diagnostics/
├── Sources/Diagnostics/DiagnosticsSnapshot.swift   # + optional frameTimings
├── Sources/Diagnostics/DiagnosticsExporter.swift   # + text lines
└── Tests/DiagnosticsTests/FrameTimingsExportTests.swift  (+ schema copy)
specs/001-ios-projectm-visualizer/contracts/diagnostics-export.schema.json   # + frameTimings
Apps/projectM-iOS/
├── Coordinators/AppCoordinator+FrameStages.swift   # attach/detach, overlay lines, export conversion
├── Visuals/*VisualHost.swift, NativeSpectrumHost.swift   # stage brackets
├── Views/PerformanceOverlay.swift, VisualizerView.swift  # stage lines
├── Automation/AutomationRunner.swift               # perf001 mode
├── Tests/FrameStageAppTests.swift
└── UITests/FrameStageOverlayUITests.swift
```

**Structure Decision**: The timer lives in a new target of the Compositor package because the Compositor
(integration test), ANGLERendering (already depends on the Compositor product) and the app all need it,
and the package is already tested on Linux. Diagnostics keeps its own Codable export type so it gains
no dependency.

## Complexity Tracking

None.
