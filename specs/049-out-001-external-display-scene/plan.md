# Implementation Plan: OUT-001 External Display Scene

**Branch**: `feature/out-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/049-out-001-external-display-scene/spec.md`

## Summary

The app adopts UIKit's non-interactive external display scene role
(`UIWindowSceneSessionRoleExternalDisplayNonInteractive`, iOS 16+, current in the iOS 27.2 SDK)
through a `UIApplicationDelegateAdaptor` whose `configurationForConnecting` returns a
configuration with `ExternalDisplaySceneDelegate` for that role and leaves the application role to
SwiftUI (research OUT-001-D1). The external scene's window holds one black `VisualSlotView`. The
visualizer screen holds another. An `ExternalDisplayCoordinator` (app, main actor) feeds scene
events into `ExternalDisplayRouting` (a pure value in `PresentationLifecycle`, tested on the host
and on Linux), which decides the output target. The coordinator then moves the *one* current visual
view (the ANGLE renderer's view, or the native spectrum, Camera or Photo host's view) into the
target slot. SwiftUI never owns a visual view, only its slot (OUT-001-D3). Each visual already lays
out its drawable from its view's bounds and trait display scale, so moving the view makes it render
at the external screen's size and scale with the same renderer, the same compositor and the same
flash limiting, and no second context or engine (OUT-001-D2). The device shows the controls over
black with the note "Showing on external display". The Camera and Photo hosts ignore scene events
from external display scenes (OUT-001-D4). ADR-0023 records the scene architecture.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the build Mac; Xcode 26 / iOS SDK 26.5 in CI).

**Primary Dependencies**: UIKit (scene roles, `UIWindowSceneDelegate`, `traitOverrides`), SwiftUI
(`UIApplicationDelegateAdaptor`, `UIViewRepresentable`), the existing visual hosts, Compositor,
ANGLERendering. No new package dependency; no `Package.swift` change except new test files.

**Storage**: none (no setting; the routing is session state).

**Testing**: `swift test --package-path Packages/PresentationLifecycle` (routing rules, host and
Linux); Compositor GPU tests (1920 × 1080 output, size switch mid-strobe); an ANGLERendering
simulator test (strobe history across a resize); app unit tests (`ExternalDisplayCoordinatorTests`:
coordinator plus real slot views, Camera host drawable at an external size and scale via
`traitOverrides`, scene-role filter); one UI test with a DEBUG fake external window (connect,
disconnect, source starts); the simulator's TVOut display turned on and off with
`xcrun simctl io <udid> screenConfig --display external power on|off` (research OUT-001-D6).

**Target Platform**: iOS/iPadOS 26+.

**Project Type**: mobile app (app target plus one package addition).

**Performance Goals**: one visualization drawn at a time (no double GPU cost); the move happens on
the next main-run-loop turn after the scene event (≤ 0.5 s, OUT-001-R6); no per-frame allocation.

**Constraints**: public APIs only; APIs newer than iOS 26 availability-guarded (none needed:
everything used is iOS 16-17); explicit closure types; no main-actor mutation in
setUp/tearDown; no wall-clock assertions; owner rule 7 budgets; never the Simulator panel tool.

**Scale/Scope**: about 450 lines of source and 450 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | UIKit scene roles and delegates, SwiftUI adaptor; no private API | Pass |
| IV/V. Truthful labeling, no universal claims | No compatibility claim; device checks are `{device}` tasks | Pass |
| VI. Modular boundaries | Routing rules in `PresentationLifecycle` (pure Swift, no UIKit); UIKit glue in the app | Pass |
| VII. Real-time audio safety | No audio-path change; the source is never touched by routing | Pass |
| VIII. Upstream fidelity | projectM and ANGLE untouched | Pass |
| X. Evidence | Host, Linux, simulator tests; simulator never device evidence; S6 left to the owner | Pass |
| Privacy / local-first | No network, no stored data; the camera keeps its CAM-012 badge on the device | Pass |
| Flash safety (ADR-0011, ADR-0013 decision 6) | Same renderer and compositor draw the external output; history kept across the move | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/049-out-001-external-display-scene/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/external-display.md
└── checklists/requirements.md
docs/adr/0023-external-display-scene.md
```

### Source Code (repository root)

```text
Packages/PresentationLifecycle/Sources/PresentationLifecycle/ExternalDisplayRouting.swift   # NEW: rules (pure Swift)
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/ExternalDisplayRoutingTests.swift
Packages/Compositor/Tests/CompositorTests/ExternalOutputSizeTests.swift                    # 1920×1080, strobe across a switch
Packages/ANGLERendering/Tests/ANGLERenderingTests/FlashLimiterTests.swift                   # + history across a resize
Apps/projectM-iOS/ProjectMApp.swift                       # + UIApplicationDelegateAdaptor
Apps/projectM-iOS/ExternalDisplay/AppDelegate.swift       # NEW: scene configuration per role
Apps/projectM-iOS/ExternalDisplay/ExternalDisplaySceneDelegate.swift   # NEW: the external window
Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift     # NEW: events → routing → slot moves
Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift    # NEW: slot view + SwiftUI host
Apps/projectM-iOS/Views/VisualizerView.swift              # visual hosted through slots; note when external
Apps/projectM-iOS/Visuals/CameraVisualHost.swift, PhotoVisualHost.swift   # ignore external scenes' events
Apps/projectM-iOS/Coordinators/AppCoordinator.swift       # owns the coordinator; visualizer active flag
Apps/projectM-iOS/Debug/UITestExternalDisplay.swift       # NEW (DEBUG): fake external window for UI tests
Apps/projectM-iOS/Tests/ExternalDisplayCoordinatorTests.swift
Apps/projectM-iOS/UITests/ExternalDisplayUITests.swift
```

**Structure Decision**: rules where they can be tested anywhere (package); UIKit and SwiftUI
glue in the app, under one new folder (`project.yml` already includes `Apps/projectM-iOS`).

## Complexity Tracking

None: no constitution violation.
