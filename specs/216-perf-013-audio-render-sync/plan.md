# Implementation Plan: PERF-013 Audio-render synchronization

**Branch**: `feature/perf-013` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/216-perf-013-audio-render-sync/spec.md`

## Summary

Three layers, each extending what exists:

1. **FrameTiming (Compositor package, no dependencies, Linux-built)**: `AudioClockDriftEstimator` (pure value:
   1 s buckets of minimum arrival residuals, least-squares slope over up to 64 buckets, detection hysteresis, step
   restart; preallocated) and `FeatureAgeMeter` (a `Mutex` around the estimator, the bounded correction, the last
   consumed frame stamp, an EMA and two `FrameIntervalHistogram`s reused from PERF-012: the counting session's and
   the app session's). Pure functions of injected times: no clock read inside (research PERF-013-D1 to D4).
2. **VisualGenerators (`LiveBandFrameInfo`)**: gains `sessionSample` (the bus frame's `time.sessionSample`), so a
   visual can hand the meter the frame's sample position. Additive field with a default.
3. **App**: `FeatureAgeMeasured` protocol on the native, camera, photo, video and text hosts (one optional
   `featureAge` property and one call per frame after `readLatest`, before present: presentation = display-link
   target time, arrival = `MonotonicClock` at read); `FeatureAgeAttachment` (attached to the shown visual while the
   overlay is shown, like PERF-007's attachment; a new counting session on each attach); the overlay line after
   the frame-drop lines; drift verdict signposts from the overlay refresh (`DiagnosticsLog.audioSync`); the PERF-012
   report's optional `audioSync` section (`PerformanceReport.AudioSync`, schema version 1 amended: spec
   Clarifications).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26, Linux Swift for the packages)
**Primary Dependencies**: Synchronization (`Mutex`), os (`OSSignposter`) via Diagnostics, QuartzCore display link
**Storage**: none (in memory for the app session)
**Testing**: XCTest — FrameTimingTests (estimator and meter acceptance with injected clocks), DiagnosticsTests (report
schema), app unit tests (attachment, overlay line, report section) on "PERF13 iPhone 17" (iOS 27.2)
**Target Platform**: iOS/iPadOS 26+
**Performance Goals**: per frame one uncontended lock, O(1) work, zero allocations; the slope fit (≤ 64 points)
runs once per second of audio
**Constraints**: no networking, no stored key, nothing to projectM; Linux-buildable packages; no wall-clock asserts
**Scale/Scope**: 2 new FrameTiming files, 1 VisualGenerators field, ~3 app files, 5 one-line host hooks

## Constitution Check

| Principle | Check |
|---|---|
| I Public Apple APIs only | `CADisplayLink.targetTimestamp`, `clock_gettime_nsec_np`, `OSSignposter`: public. PASS |
| VI Modular boundaries | Estimator in FrameTiming (pure), report type in Diagnostics, wiring in the app. PASS |
| VII Real-time audio safety | Nothing on an audio callback; frame path allocates nothing. PASS |
| VIII Upstream projectM fidelity | Nothing passed to projectM; projectM's path shows "unavailable". PASS |
| X Evidence-based quality | Acceptance by injected-clock unit tests; device plausibility left as `{device}`. PASS |
| Privacy | Numbers only; report section additive and local. PASS |

Post-design re-check: PASS (no new entitlement, permission, network symbol or UserDefaults key).

## Project Structure

```text
Packages/Compositor/Sources/FrameTiming/AudioClockDriftEstimator.swift      (new)
Packages/Compositor/Sources/FrameTiming/FeatureAgeMeter.swift               (new)
Packages/Compositor/Tests/FrameTimingTests/AudioClockDriftTests.swift       (new, acceptance)
Packages/Compositor/Tests/FrameTimingTests/FeatureAgeMeterTests.swift       (new)
Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift     (sessionSample)
Packages/Diagnostics/Sources/Diagnostics/PerformanceReport.swift            (AudioSync section)
Packages/Diagnostics/Sources/Diagnostics/Logging.swift                      (audioSync signpost)
Packages/Diagnostics/Tests/DiagnosticsTests/PerformanceReportTests.swift    (section validates)
specs/209-perf-012-performance-report/contracts/performance-report.schema.json (+ test copy; amended)
Apps/projectM-iOS/Visuals/FeatureAgeMeasuring.swift                         (new: protocol, frame helper)
Apps/projectM-iOS/Coordinators/AppCoordinator+FeatureAge.swift              (new: attachment, lines, signposts)
Apps/projectM-iOS/Coordinators/PerformanceReportBuilder.swift               (audioSync)
Apps/projectM-iOS/Tests/FeatureAgeAppTests.swift                            (new)
```

**Structure Decision**: extend existing packages; no new package (no CI group change).

## Complexity Tracking

None.
