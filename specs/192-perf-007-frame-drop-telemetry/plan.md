# Implementation Plan: PERF-007 Frame drop telemetry

**Branch**: `feature/perf-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/192-perf-007-frame-drop-telemetry/spec.md`

## Summary

A lock-free, preallocated `FrameDropCounter` (pure Swift, `FrameTiming` target of Packages/Compositor, next to
PERF-001's `FrameStageTimer`) counts submitted frames and skipped refresh slots from display-link timestamps, and
presented, late and discarded frames from the display's presented reports, per session token. Each 64-bit atomic
cell packs the session generation with its value, so a report of an old session can never change a new session's
counts, and the newest-presented cell packs the generation, the newest frame ID and a 16-frame window bitmask, so a
repeated report is never counted twice. The app keeps one counter for the device display and one for the external
display, attaches the right one to the shown visual while the performance overlay is shown (the PERF-001
attachment), starts a session when the visual, its output or the overlay changes, and builds the recording's counts
from REC-003/REC-006 statistics. The overlay gets `frames <output>` lines; the diagnostics snapshot gets an
optional `frameDrops` section, filled by the automation runner's perf001 mode.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26 and Linux)
**Primary Dependencies**: Synchronization (`Atomic`, macOS 15 / iOS 18 / Linux) for the counter; QuartzCore/Metal
in the app (`CADisplayLink`, `CAMetalDrawable.addPresentedHandler`, `presentedTime`)
**Storage**: none (in memory only; no UserDefaults key)
**Testing**: XCTest: FrameTimingTests (acceptance, duplicates, stale sessions, separation, unavailable; host and
Linux), DiagnosticsTests (round trip, schema), app unit tests on simulator "PERF7" (device counters with an injected
clock, attachment sessions, overlay lines)
**Target Platform**: iOS/iPadOS 26+, macOS host tests, Linux for the core
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: frame path: a few atomic operations per frame, no lock, no allocation (beyond Metal's handler block)
**Constraints**: never double-count; unavailable never shown as 0; no network
**Scale/Scope**: three outputs; one visual at a time

## Constitution Check

| Principle | Check |
|---|---|
| I. Public Apple APIs only | `CADisplayLink`, `CAMetalDrawable.addPresentedHandler`, `MTLDrawable.presentedTime`, Swift `Atomic`. Pass. |
| VI. Modular boundaries | The counter is in FrameTiming (no dependencies); ANGLERendering already depends on it; Diagnostics gains plain value types. Pass. |
| VII. Real-time audio safety | Nothing touches an audio callback. Pass. |
| X. Evidence-based quality | Injected events and clocks; simulator results are not performance evidence; device counts with an external display are a `{device}` task. Pass. |
| Privacy / no telemetry (Platform constraints) | Local counting only, no network, no stored data; export only in the file the user shares by hand. Pass. |

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/Compositor/Sources/FrameTiming/FrameDropCounter.swift      # output, session, ticket, counts, counter
Packages/Compositor/Tests/FrameTimingTests/FrameDropCounterTests.swift
Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift  # frameDrops property, submit on each presented tick
Packages/Diagnostics/Sources/Diagnostics/DiagnosticsSnapshot.swift  # optional frameDrops section
Packages/Diagnostics/Tests/DiagnosticsTests/FrameDropsExportTests.swift
specs/001-ios-projectm-visualizer/contracts/diagnostics-export.schema.json (+ test resource copy)
Apps/projectM-iOS/Visuals/FrameDropCounting.swift                   # protocol, drawable helper
Apps/projectM-iOS/Coordinators/AppCoordinator+FrameDrops.swift      # attachment, lines, export
Apps/projectM-iOS/Coordinators/AppCoordinator+FrameStages.swift     # one call: lines appended
Apps/projectM-iOS/Visuals/{NativeSpectrum,Camera,Photo,Video,Text}*Host.swift   # property + one line before present
Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift      # current statistics accessor
Apps/projectM-iOS/Views/PerformanceOverlay.swift                    # frames lines in their own text
Apps/projectM-iOS/Automation/AutomationRunner.swift                 # perf001 adds frameDrops
Apps/projectM-iOS/Tests/FrameDropAppTests.swift
```

## Complexity Tracking

None.
