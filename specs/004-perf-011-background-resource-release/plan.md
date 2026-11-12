# Implementation Plan: PERF-011 Background resource release

**Branch**: `feature/perf-011` | **Date**: 2026-11-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/004-perf-011-background-resource-release/spec.md`

## Summary

When the app cannot present frames (background or device lock, not the inactive state), every
presentation-bound resource is suspended exactly once and resumed exactly once on return. A small
pure-Swift package, `PresentationLifecycle`, holds the availability state machine, the resource
protocol and the registry; it is tested on the macOS host. The two renderers and the preset
warm-up adopt the protocol: the frame loop is stopped under a suspension flag that is independent
of user pause, the ANGLE window surface and Reduce-flashing target are released and recreated, and
the warm-up thread, context and engine are torn down and restartable. The app's existing
`LifecycleCoordinator` drives the registry from the events it already handles. Capture behavior is
not touched.

## Technical Context

**Language/Version**: Swift 6.4.2 (strict concurrency), Xcode 27.2 / iOS SDK 27.2 (ADR-0002)

**Primary Dependencies**: none new. Existing: UIKit, QuartzCore (`CADisplayLink`), ANGLE (EGL on
Metal, ADR-0003), `ProjectMBridge`, `Diagnostics` (`OSSignposter`)

**Storage**: none (spec R14). Nothing is persisted, so there is no migration.

**Testing**: XCTest. `PresentationLifecycle` and `Diagnostics` on the macOS host with `swift test`;
`Rendering` and `ANGLERendering` on an iOS 27.2 simulator with `xcodebuild test`; app unit tests
(`Apps/projectM-iOS/Tests`) in the app scheme, run by the main session after the merge.

**Target Platform**: iOS and iPadOS 26.0+; the new package also builds for macOS 15 and Linux
(tests only).

**Project Type**: mobile app with SwiftPM packages under `Packages/`

**Performance Goals**: zero frames drawn and zero warm-up work while suspended; resume within the
2 s feature 001 already allows for the audio (FR-050). Device figures are spec S7 and S8.

**Constraints**: public Apple APIs only; no new entitlement, background mode, permission or
networking; no change to `CaptureKit`; suspend may block the main thread only for the warm-up
thread's current engine call (clarification 4).

**Scale/Scope**: one new package (about 150 lines), changes in 2 renderers, 1 warm-up class, 2 app
coordinators, 1 diagnostics helper, CI package lists and `project.yml`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Note |
|---|---|---|
| I. Public Apple APIs only | Pass | `CADisplayLink`, EGL through ANGLE, `OSSignposter`; no new system observer. `check_compliance.py` runs before each commit. |
| II-V. Capture feasibility, strategy, labeling, claims | Pass | No capture code, label or claim changes (R11). |
| VI. Modular boundaries | Pass | The registry knows only the resource protocol. `Rendering` still does not import `CaptureKit`; the new package imports nothing. The app maps `AppLifecycleEvent` to `PresentationSignal`. |
| VII. Real-time audio safety | Pass | No code on audio callbacks changes. The warm-up wait happens on the main thread, never on an audio thread. |
| VIII. Upstream ProjectM fidelity | Pass | `Vendor/` untouched; the engine is used through `ProjectMBridge` as before. |
| IX. Pinned dependencies and licenses | Pass | No new dependency. |
| X. Evidence-based quality | Pass | Deterministic unit tests for the logic; simulator tests for surface and warm-up teardown; S7 and S8 are tagged `{device}` and not claimed. |
| Privacy | Pass | The transition report carries a flag and three counts, no user content (R12). |
| Workflow | Pass | specify → clarify → plan → tasks → analyze → implement on `feature/perf-011`; nothing pushed (run rule). |

Post-design re-check (after Phase 1): unchanged, all pass. One structural addition is recorded in
Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/004-perf-011-background-resource-release/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/presentation-resources.md
├── checklists/requirements.md
└── tasks.md            # /speckit-tasks
```

### Source Code (repository root)

```text
Packages/PresentationLifecycle/                       # NEW, pure Swift, host-testable
├── Package.swift
├── Sources/PresentationLifecycle/
│   ├── PresentationAvailability.swift                # signals → canPresent (R1)
│   └── PresentationResourceRegistry.swift            # protocol, registry, report (R2-R4, R12)
└── Tests/PresentationLifecycleTests/
    ├── PresentationAvailabilityTests.swift
    └── PresentationResourceRegistryTests.swift

Packages/Rendering/
├── Package.swift                                      # + dependency on PresentationLifecycle
├── Sources/Rendering/VisualizerRenderer.swift         # + presentationResources (default: none)
├── Sources/Rendering/GLESRenderer.swift               # loop obeys suspension (R9)
└── Tests/RenderingTests/GLESRendererTests.swift       # + suspension tests

Packages/ANGLERendering/
├── Package.swift                                      # + dependency on PresentationLifecycle
├── Sources/ANGLERendering/ANGLERenderer.swift         # suspension flag, surface release (R5, R6)
├── Sources/ANGLERendering/PresetPrewarmer.swift       # restartable stop, safe points (R7)
├── Sources/ANGLERendering/PresetWarmUpController.swift  # NEW: delay, last request, suspension (R7, R8)
└── Tests/ANGLERenderingTests/
    ├── ANGLERendererTests.swift                       # + suspension tests
    └── PresetWarmUpControllerTests.swift              # NEW: fake worker and real prewarmer

Packages/Diagnostics/Sources/Diagnostics/Logging.swift # + presentation transition signpost (R12)

Apps/projectM-iOS/
├── Coordinators/LifecycleCoordinator.swift            # availability + registry (R1, R10)
├── Coordinators/AppCoordinator.swift                  # owns the registry, registers the renderer
└── Tests/LifecycleCoordinatorTests.swift              # + registry and unlock-in-background tests

project.yml                                            # + PresentationLifecycle package for projectM-iOS
.github/workflows/ios-ci.yml                           # + PresentationLifecycle in the package loops
```

**Structure Decision**: Existing packages are extended wherever the code belongs to them. The one
new package exists because the registry must be testable on the macOS host and usable by a later
camera layer, and no existing package fits: `Rendering` and `ANGLERendering` build only for iOS
and link the engine; `CaptureKit` may not be imported by `Rendering` (its manifest and
constitution VI); `AudioCore`, `Diagnostics` and `PresetLibrary` have unrelated purposes.

## Design

### Availability (R1)

`PresentationAvailability` is a value type with two flags, `isBackgrounded` and `isLocked`, and
`canPresent = !isBackgrounded && !isLocked`.

| Signal | Effect |
|---|---|
| `enteredBackground` | `isBackgrounded = true` |
| `willEnterForeground` | `isBackgrounded = false`, `isLocked = false` |
| `locked` | `isLocked = true` |
| `unlocked` | `isLocked = false` |

The scene's inactive phase is not a signal. `LifecycleCoordinator` maps
`AppLifecycleEvent.background/.foreground/.lock/.unlock` to these four.

### Registry (R2-R4, R12, R13)

`PresentationResourceRegistry` (`@MainActor`) keeps entries in registration order, each with a weak
reference, the name and a `suspended` mark. `setCanPresent(false)` walks the entries in reverse and
suspends those not marked; `setCanPresent(true)` walks forward and resumes those marked. A repeat
of the current value does nothing. `register` ignores a resource already present and suspends a
new one at once while `canPresent` is false. `unregister` removes the entry without calling the
resource. Dead entries are dropped. Each sweep works on a copy of the entry list and re-checks
membership before each call, so a resource may register or unregister others from inside its own
callback. A change of availability made from inside a callback is applied after the running sweep.
`onTransition` receives `PresentationTransitionReport(canPresent, registered, activeBefore,
activeAfter)` after each real change.

### Renderers (R5, R6, R9)

`VisualizerRenderer` gains `presentationResources: [any PresentationBoundResource]` (default
empty), listed in registration order.

- `ANGLERenderer` returns `[self, warmUp]`. Suspension order is therefore warm-up first, then the
  frame loop and surface; resume order is surface and loop first, then warm-up.
  - New flag `presentationSuspended`, independent of `paused`.
  - Suspend: invalidate the display link; make the placeholder surface current; destroy the
    Reduce-flashing target and the window surface; `surfaceSize = (0, 0)`.
  - While suspended: `renderFrame` returns false; `layoutSurface` returns without creating a
    surface; a window change records whether a display link is wanted but starts none;
    `pause()`/`resume()` only set `paused`.
  - Resume: clear the flag; `layoutSurface()` recreates the surface at the current bounds and sets
    the engine viewport; the display link restarts if the view is in a window, paused iff `paused`.
  - `deinit` already tolerates a missing surface and limiter.
- `GLESRenderer` (fallback) returns `[self]`: the same flag for its display link and `renderFrame`.
  Its layer-backed framebuffer is kept; it is the fallback path and is not worth a second
  release-and-recreate implementation without device evidence.

### Warm-up (R7, R8)

- `PresetPrewarmer.stop()` becomes restartable: it sets `stopping`, clears the queue, waits until
  the thread has destroyed its framebuffer, engine, surface and context and cleared `thread`, then
  resets `stopping`. The thread checks `stopping` after loading a preset and after its first frame
  and does not record an interrupted preset as warmed. A failed context creation marks the
  prewarmer unavailable so requests do not spawn threads repeatedly. `isRunning` and
  `hasGraphicsContext` expose the state to tests.
- `PresetWarmUpController` (`@MainActor`, new) takes over what `ANGLERenderer.prewarm` did (the
  delay task) behind a `PresetWarming` worker protocol, so it can be tested with a fake worker. It
  remembers the last request. Suspend cancels the delay task and calls `worker.stop()`; resume
  issues the remembered request again with the normal delay; a request made while suspended is
  only remembered. `ANGLERenderer.prewarmEnabled`, `prewarmDelay` and `prewarmedCount` keep their
  names and forward to it.

### App (R10, R11, R12)

- `LifecycleCoordinator` gains a `PresentationAvailability` and a registry (injected, default new).
  `handle(_:)` applies the event; on loss it suspends the visualization (if visualizing) and then
  the registry; on regain it resumes the registry and then the visualization (if visualizing and
  not user-paused); then it forwards the event to `CaptureManager` exactly as before. `suspended`
  becomes `!availability.canPresent`.
- `AppCoordinator` owns the registry, passes it to `LifecycleCoordinator`, registers
  `renderer.presentationResources` in `prepareRenderer()`, and sets `onTransition` to
  `DiagnosticsLog.presentationTransition`, which emits one signpost event.
- `ProjectMApp`, `IdleTimerPolicy` and `CaptureKit` are unchanged.

### Test design (deterministic)

| Level | Where | What |
|---|---|---|
| Host unit | `PresentationLifecycleTests` | availability truth table; order; exactly-once; late registration; unregister; dealloc; duplicate; reentrancy; reports; a seeded 100-signal sequence (S4) |
| Simulator unit | `PresetWarmUpControllerTests` (fake worker) | suspend cancels the delay and stops the worker once; resume reissues; request while suspended; disabled; repeated suspend/resume |
| Simulator unit | `PresetWarmUpControllerTests`, `ANGLERendererTests` (real EGL) | prewarmer has no thread or context after stop and warms again after restart; renderer has no surface, no display link and draws nothing while suspended; resumes with the same preset lit; user pause survives; layout while suspended creates nothing; size change while suspended; deinit while suspended |
| Simulator unit | `GLESRendererTests` | the fallback loop obeys suspension |
| App unit (after merge) | `LifecycleCoordinatorTests` | registry driven in every mode and on the chooser; unlock while backgrounded resumes nothing; foreground clears a lock; existing matrix tests unchanged |
| `{device}` | final stage | S7 (GPU time, memory) and S8 (app switcher card, first frame) |

### Persistence and rollback

No persisted state and no setting (R14), so there is nothing to migrate or restore. Rollback is
`git revert` of the feature's commits; the app then behaves as at `e679131`.

## Complexity Tracking

| Addition | Why needed | Simpler alternative rejected because |
|---|---|---|
| New package `PresentationLifecycle` | Host-testable registry that renderers now and camera/media layers later can adopt without importing each other | Putting it in `Rendering` makes it iOS-only (no host tests) and forces a future camera package to link the engine; putting it in `CaptureKit` breaks `Rendering`'s rule of not importing it |
