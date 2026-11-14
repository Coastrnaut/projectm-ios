# Implementation Plan: PERF-012 Diagnostic performance report

**Branch**: `feature/perf-012` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/209-perf-012-performance-report/spec.md`

## Summary

Three layers, each extending what exists:

1. **FrameTiming (Compositor package)**: `FrameIntervalHistogram` (pure value: 0.1 ms buckets to 250 ms, exact max,
   sum, long-frame counts, nearest-rank percentiles) and `FrameIntervalRecorder` (a `Mutex` around one preallocated
   histogram). `FrameDropCounter.init(intervals:)` feeds it from `submit`, which every visual path already calls with
   display-link timestamps while the performance overlay is shown (PERF-007). No new per-frame hook in any visual.
2. **Diagnostics package**: `PerformanceReport` (Codable, `schemaVersion` 1, `kind`), reusing
   `DiagnosticsSnapshot.Device`, `App`, `FrameTimings` and `FrameDrops`; every free string is either sanitised system
   metadata or a member of a fixed set (unknown → `unknown`). `DiagnosticsExporter` gains `performanceReportName(for:)`
   and `encode(_: PerformanceReport)`. `DiagnosticsLog.performanceReport(_:)` emits the signpost event. Contract
   `contracts/performance-report.schema.json` (copied into the test resources; a script test keeps the copy equal).
3. **App**: `PerformanceStateRecorder` (launch time, thermal/Low Power/profile/cap/scale timeline from
   `QualityGovernor.changeNotifications`, at most 200 entries, peak memory footprint); `PerformanceReportBuilder`
   (inputs → report: histogram, PERF-007 counts, PERF-001/002 timings when the timer is attached, pool counters,
   memory); `PerformanceReportExport` (REC-012 `ShareFileStore` copy + `ActivitySharePresenter`, new share kind
   `performanceReport`, DEBUG `-uitestShareSimulation`); `PerformanceReportSection` in Settings → Performance.
   `FrameDropAttachment` owns the shared `FrameIntervalRecorder` and builds both counters with it.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26, Linux Swift 6.4.2 for the packages)
**Primary Dependencies**: Foundation, Synchronization (`Mutex`), os (`OSSignposter`), Darwin (`task_info`
TASK_VM_INFO `phys_footprint`, `os_proc_available_memory`) in the app only, UIKit share sheet
**Storage**: none (in memory for the app session; the exported file is a temporary share copy)
**Testing**: XCTest — FrameTiming (Compositor) and Diagnostics package tests on the host; app unit tests and one UI
test on the feature simulator "PERF12 iPhone 17" (iOS 27.2)
**Target Platform**: iOS/iPadOS 26+
**Performance Goals**: zero allocations per frame; one uncontended lock per submitted frame while the overlay is shown
**Constraints**: no networking, no new preference key, no user content in the file; Linux-buildable packages
**Scale/Scope**: ~6 new source files, 2 package extensions, 1 Settings section

## Constitution Check

| Principle | Check |
|---|---|
| I Public Apple APIs only | `task_info`, `os_proc_available_memory`, `UIActivityViewController`, `OSSignposter`: public. PASS |
| VI Modular boundaries | Histogram in FrameTiming, report model in Diagnostics, gathering in the app. PASS |
| VII Real-time audio safety | Nothing on an audio thread; the frame-thread path allocates nothing. PASS |
| X Evidence-based quality | Percentile maths and privacy unit-tested; device figures left as a `{device}` task. PASS |
| Privacy constraints (FR-021, FR-061, FR-068) | User-initiated local file; metadata only; no identifiers; nothing sent. PASS |

Post-design re-check: PASS (no new entitlement, permission, network symbol or stored key).

## Project Structure

```text
Packages/Compositor/Sources/FrameTiming/FrameIntervalHistogram.swift      (new)
Packages/Compositor/Sources/FrameTiming/FrameDropCounter.swift            (intervals feed)
Packages/Compositor/Tests/FrameTimingTests/FrameIntervalHistogramTests.swift (new)
Packages/Diagnostics/Sources/Diagnostics/PerformanceReport.swift          (new)
Packages/Diagnostics/Sources/Diagnostics/DiagnosticsExporter.swift        (name + encode)
Packages/Diagnostics/Sources/Diagnostics/Logging.swift                    (signpost)
Packages/Diagnostics/Tests/DiagnosticsTests/PerformanceReportTests.swift  (new)
Packages/Diagnostics/Tests/DiagnosticsTests/Resources/performance-report.schema.json (copy of the contract)
Apps/projectM-iOS/Coordinators/PerformanceReport*.swift                   (recorder, builder, export)
Apps/projectM-iOS/Views/PerformanceReportSection.swift                    (new)
Apps/projectM-iOS/Tests/PerformanceReportAppTests.swift                   (acceptance)
Apps/projectM-iOS/UITests/PerformanceReportUITests.swift                  (export flow)
```

**Structure Decision**: extend the existing packages; no new package (no CI group change).

## Complexity Tracking

None.
