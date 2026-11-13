# Implementation Plan: PERF-006 Memory Warning Recovery

**Branch**: `feature/perf-006` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/054-perf-006-memory-warning-recovery/spec.md`

## Summary

`MemoryPressureRecovery` (new, `PresentationLifecycle` package, pure Swift, main actor) keeps weak,
owner-registered responders with a name, a tier (`cache` or `optional`) and a reclaimable-bytes
estimate. `handle(_ level:at:)` runs every cache responder in registration order and, when the signal
escalates (critical, or a warning within 30 s of the previous one), every optional responder, which
then stays shed until 60 s after the last escalating signal; `restoreIfDue(at:)` restores each shed
responder once. Re-entrant signals are queued and handled after the running one. Each call returns a
`MemoryPressureReport` (per-step freed bytes and items, measured or estimated). Time is an injected
monotonic value in seconds, so tests use a test clock.

The app's `MemoryPressureCoordinator` (`shared`) is the only observer of
`UIApplication.didReceiveMemoryWarningNotification` (PERF-004's `SharedTexturePool` observer moves into
it), owns the restore timer, logs `DiagnosticsLog.memoryRecovery` and keeps the last report for the
DEBUG readout. Responders:

| Step | Owner | Tier | Frees | Bytes |
|---|---|---|---|---|
| shared texture pool | app `SharedTexturePool` | cache | every retired picture of every pool (PERF-004-R5) | measured (retired bytes) |
| preset warm-up context | `ANGLERendering` `PresetWarmUpController` | cache | cancels a waiting request; stops the worker: thread, EGL context, engine, 256² target (PERF-011-R7) | estimated (target size) |
| preset warm-up | same | optional | holds new requests for the cool-down; restore issues the newest | 0 |
| preset archive cache | app `RendererPresetLoader` | cache | the decompressed chunk | measured |
| idle native spectrum | app `AppCoordinator` | cache | a spectrum host that is not the chosen visual (with its glow images) | items only |

`VisualizerRenderer` gains `memoryPressureResponders` (default empty); `ANGLERenderer` returns its
warm-up's two steps. The DEBUG launch flag `-uitestMemoryPressure` shows a probe (inject a warning by
posting the system notification, inject a critical signal) and readouts.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the build Mac; Xcode 26 / iOS SDK 26.5 in CI).

**Primary Dependencies**: UIKit (notification), Foundation; existing PresentationLifecycle,
ANGLERendering, Rendering, Compositor, Diagnostics packages. No new package or dependency.

**Storage**: none (nothing stored; settings untouched).

**Testing**: `swift test --package-path Packages/PresentationLifecycle` (host and Linux shape: the
recovery with fake responders and a test clock); `swift test --package-path Packages/Diagnostics`
(summary text); `xcodebuild test -scheme ANGLERendering` on the iOS 27.2 simulator (controller with a
fake worker; real prewarmer releases its context); app unit tests (`MemoryPressureAppTests`: pool,
archive, idle spectrum, coordinator wiring, steady-size frames after recovery); app UI test
`MemoryPressureUITests` (projectM, Camera stand-in, Photo) plus CameraUITests, PhotoLayerUITests,
NativeVisualUITests.

**Target Platform**: iOS/iPadOS 26+ (macOS 15 host and Linux for the package core).

**Project Type**: mobile app plus Swift packages.

**Performance Goals**: a recovery is a few main-actor calls; the warm-up stop waits at most one
engine call (PERF-011). Nothing on a per-frame path changes; no allocation per frame afterwards.

**Constraints**: public APIs only; explicit closure types; no C stdio globals; no main-actor mutation
in setUp/tearDown; no wall-clock assertions (test clock; waits are ceilings); owner rule 7 budgets;
never the Simulator panel tool.

**Scale/Scope**: about 400 lines of source, 500 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | `UIApplication.didReceiveMemoryWarningNotification`, `NotificationCenter`, EGL calls already used by the warm-up | Pass |
| IV. Truthful source labeling | Recovery never touches the source or its state | Pass |
| VI. Modular boundaries | Recovery core in PresentationLifecycle (no imports); steps live with their owners; the renderer exposes steps through the `VisualizerRenderer` protocol | Pass |
| VII. Real-time audio safety | Nothing runs on or waits for the audio thread; the source is not stopped | Pass |
| VIII. Upstream fidelity | projectM and ANGLE untouched | Pass |
| X. Evidence | Unit, host, simulator tests; injection is simulated and labelled so; device pressure is a `{device}` task | Pass |
| Privacy | Diagnostics carry step names and counts only | Pass |

Post-design re-check: unchanged, all pass. No ADR needed: no constitution default is overridden and
the decisions are recorded in research.md (PERF-006-D1 to D8).

## Project Structure

### Documentation (this feature)

```text
specs/054-perf-006-memory-warning-recovery/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/memory-pressure-recovery.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/PresentationLifecycle/Sources/PresentationLifecycle/MemoryPressureRecovery.swift   # NEW: levels, tiers, responder protocol, recovery, report
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/MemoryPressureRecoveryTests.swift   # NEW: fakes + test clock (Linux)
Packages/Diagnostics/Sources/Diagnostics/Logging.swift            # memoryRecovery event + summary
Packages/Diagnostics/Tests/DiagnosticsTests/MemoryRecoveryLogTests.swift   # NEW
Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift     # memoryPressureResponders (default [])
Packages/ANGLERendering/Sources/ANGLERendering/PresetWarmUpController.swift   # two steps; shedding
Packages/ANGLERendering/Sources/ANGLERendering/PresetPrewarmer.swift  # holdsGraphicsResources
Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift    # exposes the steps
Packages/ANGLERendering/Tests/ANGLERenderingTests/PresetWarmUpMemoryTests.swift   # NEW
Apps/projectM-iOS/Coordinators/MemoryPressureCoordinator.swift   # NEW: the one observer, timer, log
Apps/projectM-iOS/Visuals/SharedTexturePool.swift                # step instead of its own observer
Apps/projectM-iOS/Coordinators/PresetArchive.swift               # dropCache()
Apps/projectM-iOS/Coordinators/AppCoordinator.swift              # registers steps; idle spectrum step; loader step
Apps/projectM-iOS/Debug/UITestMemoryPanel.swift                  # NEW: DEBUG probe and readouts
Apps/projectM-iOS/Views/VisualizerView.swift                     # shows the panel under the flag
Apps/projectM-iOS/Tests/MemoryPressureAppTests.swift             # NEW
Apps/projectM-iOS/UITests/MemoryPressureUITests.swift            # NEW
```

**Structure Decision**: the policy (order, escalation, cool-down) is pure and lives in the package
that already holds PERF-011's comparable registry; the app keeps only the platform signal and
wiring; each owner implements its own step.

## Complexity Tracking

None: no constitution violation.
