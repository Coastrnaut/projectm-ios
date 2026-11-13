# Implementation Plan: PERF-014 Render Failure Fallback

**Branch**: `feature/perf-014` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/057-perf-014-render-failure-fallback/spec.md`

## Summary

A plain-Swift fault model in the Compositor package (`RenderHealth.swift`: `RenderFaultReason`,
`RenderRecoveryPolicy`, `RenderRetryState`, `RenderHealth`, `RenderFaultInjection`; Linux-tested) drives
bounded, frame-counted recovery in two places:

1. **`Compositor`** (CMP-001): each layer has a retry state; a failed prepare, a missing picture or a
   serious render error is a counted fault, the layer shows its CMP-001 fallback and is touched again
   only at its back-off ticks (30, 60, 120, 240), then stays on its fallback until a reset. A
   visual-level retry state covers GPU command buffer errors (polled from the last three buffers,
   D2) and a missing composite texture; during its back-off the frame is black. `health` is the
   visual's record; `frameTicks` advance on every call. DEBUG `faultInjection` makes creation or the
   status check fail.
2. **`ANGLERenderer`** (projectM): a preset load failure is recorded (`presetLoadFailed`) and rethrown
   (FR-045 unchanged); a failed swap is a counted fault with a tick back-off and a surface rebuild at
   each retry, then the placeholder state. DEBUG `faultInjection` fails preset loads or swaps.

The app reports health from the shown visual (hosts call back when the record's revision changes),
logs `DiagnosticsLog.renderFault`, shows the record in the FR-048 overlay and a DEBUG readout, and
covers a visual in the placeholder state with a black "Visual unavailable" overlay faded over 0.5 s.
VIS-001-R16 creation failures are recorded as `visualUnavailable`.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the build Mac; Xcode 26 / iOS SDK 26.5 in CI).

**Primary Dependencies**: Metal (`MTLCommandBuffer.status`, `MTLCommandBufferError`), EGL (ANGLE swap
result), SwiftUI (overlay), os (logging); existing Compositor, ANGLERendering, Diagnostics,
FlashSafety packages. No new package; `ANGLERendering` target gains the `Compositor` product (D10).

**Storage**: none.

**Testing**: `swift test --package-path Packages/Compositor` (fault model, host and Linux shape;
GPU recovery tests on the Mac's Metal device); `xcodebuild test -scheme Compositor` once on the
simulator; `xcodebuild test -scheme ANGLERendering` (projectM faults) on the iOS 27.2 simulator;
`swift test --package-path Packages/Diagnostics`; app unit tests (`RenderFaultAppTests`) and UI test
`RenderFaultUITests`, plus NativeVisualUITests, CameraUITests, GlowUITests.

**Target Platform**: iOS/iPadOS 26+; macOS 15 host and Linux for the plain-Swift part.

**Project Type**: mobile app plus Swift packages.

**Performance Goals**: per tick, a fixed-size scan of three command buffer statuses and a few
integer compares; no allocation at a steady size (CMP-001-R9) in healthy or faulted states; prepare
only at retries (≤ 4 per episode) and resets.

**Constraints**: public APIs only; no new Metal source (SHD-011: injection makes creation throw);
explicit closure types; no C stdio globals; no main-actor mutation in setUp/tearDown; no wall-clock
assertions; owner rule 7 test budgets; Simulator panel tool never used (owner rule 8).

**Scale/Scope**: 4 compositor hosts, 1 renderer, ~11 reasons.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | ✅ Metal status/error codes, EGL swap result, SwiftUI. `check_compliance.py` run. |
| IV/V Truthful labeling, no claims | ✅ Nothing about sources; simulator evidence labelled as such. |
| VI Modular boundaries | ✅ Fault model in Compositor's CPU part; the compositor knows no app; the renderer keeps its EGL internals; the app only reads records. |
| VII Real-time audio safety | ✅ Nothing on audio threads; logging from the main actor only. |
| VIII Upstream fidelity | ✅ No engine change; failures read through the bridge's existing errors. |
| X Evidence | ✅ Unit tests for deterministic logic; device task `{device}` left open; no ADR needed (no constitution default overridden). |
| Privacy | ✅ Log carries visual kind, reason identifiers and counts only. |

Post-design re-check: unchanged (no violations; Complexity Tracking empty).

## Project Structure

### Documentation (this feature)

```text
specs/057-perf-014-render-failure-fallback/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/render-health.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/RenderHealth.swift          # new, plain Swift
Packages/Compositor/Sources/Compositor/Compositor.swift            # retries, GPU watch, health, injection
Packages/Compositor/Tests/CompositorTests/RenderHealthTests.swift  # new, host + Linux
Packages/Compositor/Tests/CompositorTests/RenderFaultRecoveryTests.swift   # new, GPU
Packages/ANGLERendering/Package.swift                              # ANGLERendering += Compositor
Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift # preset + presentation faults
Packages/ANGLERendering/Tests/ANGLERenderingTests/ANGLERenderFaultTests.swift   # new
Packages/Diagnostics/Sources/Diagnostics/Logging.swift             # renderFault event
Packages/Diagnostics/Tests/DiagnosticsTests/RenderFaultLogTests.swift   # new
Apps/projectM-iOS/Visuals/{Camera,Photo,Video,Text}VisualHost.swift   # reset + report
Apps/projectM-iOS/Visuals/RenderPlaceholder.swift                  # new: fade rule + view
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                # routing, logging, injection
Apps/projectM-iOS/Views/VisualizerView.swift, PerformanceOverlay.swift
Apps/projectM-iOS/Debug/UITestRenderFaultPanel.swift               # new, DEBUG
Apps/projectM-iOS/Tests/RenderFaultAppTests.swift                  # new
Apps/projectM-iOS/UITests/RenderFaultUITests.swift                 # new
```

**Structure Decision**: existing packages and app folders; one new plain-Swift file in Compositor.

## Complexity Tracking

None.
