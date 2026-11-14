# Implementation Plan: PRE-009 Preset Comparison

**Branch**: `feature/pre-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Two presets preview side by side in a Compare sheet opened from the browser. One shared timeline on the main
thread (the live reader's only consumer) stamps each tick with its frame time and sample range and posts it to a
coalescing mailbox. A single worker thread in `ANGLERendering` (`PresetComparisonRunner`, built like
`PresetThumbnailRunner`) owns two unshared EGL contexts and two engines, takes all waiting ticks as one batch and
feeds the identical batch (samples and pinned frame time) to engine A and then engine B, draws each through the
FX-019 flash pass into a 320 × 180 BGRA target and reads both back. An optional recorder captures each delivery
per engine, which is the acceptance instrument. The app's `PresetComparisonModel` drives the ticks, pauses the
main visual while the sheet is open and shows the pictures.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2; CI Xcode 26)
**Primary Dependencies**: Rendering (new pure types), ANGLERendering (runner), ProjectMBridge (`addPCMInterleavedStereo`, `setFrameTime`, `renderFrameToFramebuffer`, unchanged), CFlashLimiter, SwiftUI
**Storage**: none (in memory only; no UserDefaults key, no file)
**Testing**: XCTest: Rendering package (timeline and mailbox, pure), ANGLERendering (real engines off screen on the simulator GPU), app UI test; private simulator "PRE9 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+ (Rendering and ANGLERendering are iOS-only packages; nothing Linux-built changes)
**Performance Goals**: 30 ticks per second (15 under Low Power Mode or serious thermal state); two 320 × 180 draws and read-backs per batch
**Constraints**: engine untouched (Constitution VIII); main visual paused while comparing; at most 6 waiting ticks
**Scale/Scope**: one comparison at a time; two engines

## Constitution Check

- I Public APIs only, no networking: EGL/ANGLE and SwiftUI as today. PASS
- VI Modular boundaries: pure lockstep logic in `Rendering`, GPU work in `ANGLERendering`, UI in the app. PASS
- VII Real-time audio safety: nothing runs in an audio callback; the ring is read on the main thread as today. PASS
- VIII Upstream fidelity: no engine change; existing bridge calls only. PASS
- X Evidence: simulator tests prove lockstep and UI; GPU/thermal cost is a `{device}` task (S5). PASS

## Project Structure

```text
Packages/Rendering/Sources/Rendering/PresetComparison.swift          # tick, batch, delivery, timeline, mailbox, recorder, protocol
Packages/Rendering/Tests/RenderingTests/PresetComparisonTimelineTests.swift
Packages/ANGLERendering/Sources/ANGLERendering/PresetComparisonRunner.swift
Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift  # exposes the runner, reader; suspends it
Packages/ANGLERendering/Tests/ANGLERenderingTests/PresetComparisonRunnerTests.swift   # acceptance (S1-S3)
Apps/projectM-iOS/Coordinators/PresetComparisonModel.swift           # picks, session, tick driver, frames
Apps/projectM-iOS/Coordinators/AppCoordinator+Comparison.swift       # wiring (contents, pause/resume, clamp)
Apps/projectM-iOS/Views/PresetCompareView.swift                      # sheet, panes, pick bar
Apps/projectM-iOS/Views/PresetBrowserView.swift                      # row menu items, bar, sheet (small edits)
Apps/projectM-iOS/UITests/PresetCompareUITests.swift
Apps/projectM-iOS/Tests/PresetComparisonModelTests.swift
```

## Complexity Tracking

None: one worker thread like the existing off-screen runners; no new package.
