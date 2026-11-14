# Implementation Plan: OUT-002 Display Connect Handling

**Branch**: `feature/out-002` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/161-out-002-display-hotplug/spec.md`

## Summary

Hot-plug of an external display already moves the one visual view between slots (OUT-001) without
recreating the render session. OUT-002 makes that robust and proves it: a connect settles for 0.3 s
before the visual moves (a quick disconnect cancels it), a running recording holds the visual where
it is, connection changes are announced on their own lane, a protocol seam lets tests inject
hot-plug events, and counters show that nothing of a disconnected display stays held. The
acceptance fixture drives connect, disconnect, connect, disconnect against a running render session
with a scene and a recording and checks nothing restarted.

## Technical Context

**Language/Version**: Swift 6.4 (Xcode 27.2), strict concurrency; CI also builds with Xcode 26 / iOS SDK 26.5
**Primary Dependencies**: UIKit scenes (OUT-001's external display scene and iOS 27 accessory), `PresentationLifecycle` package
**Storage**: none (no new keys)
**Testing**: XCTest: `PresentationLifecycle` package tests (host, Linux), app unit tests on the iOS 27.2 simulator, one UI test with the DEBUG fake display
**Target Platform**: iOS/iPadOS 26.5 and 27
**Project Type**: mobile app plus SwiftPM packages
**Performance Goals**: no per-frame cost; settle 0.3 s (inside OUT-001-R6's 0.5 s)
**Constraints**: public APIs only; no wall-clock assertions (manual settle scheduler, injected frame clock); unit tests ≤ 10 s, UI test ≤ 30 s
**Scale/Scope**: one pure type in a package, changes in `ExternalDisplayCoordinator`, a small hook in `VideoRecordingCoordinator`, two status-event rows

## Constitution Check

| Principle | Check |
|---|---|
| I Public APIs only | UIKit scenes, `UIWindow`, Swift concurrency; nothing private. PASS |
| VI Modular boundaries | The settle and hold rules are pure Swift in `PresentationLifecycle` (Linux-tested); UIKit stays in the app. PASS |
| VII Real-time audio safety | Nothing touches the audio path. PASS |
| X Evidence-based quality | Simulator and fakes are not device evidence; physical hot-plug is a `{device}` task. PASS |
| Privacy | No stored data, no network; logs carry sizes only. PASS |

Post-design re-check: unchanged, PASS.

## Project Structure

### Documentation (this feature)

```text
specs/161-out-002-display-hotplug/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
└── contracts/hot-plug.md
```

### Source Code (repository root)

```text
Packages/PresentationLifecycle/Sources/PresentationLifecycle/HotPlugSettle.swift          (new: settle + hold rules)
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/HotPlugSettleTests.swift  (new)
Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift   (settle, hold, counters, sink protocol, announcements)
Apps/projectM-iOS/Coordinators/AppCoordinator+ExternalDisplay.swift  (new: wiring to recording and status events)
Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift       (onStateChange hook)
Apps/projectM-iOS/Coordinators/StatusEvents.swift, AccessibilityAnnouncer.swift (X27, X28; `display` lane)
Apps/projectM-iOS/Debug/UITestExternalDisplay.swift                  (bounce button, resource probe)
Apps/projectM-iOS/Tests/HotPlugAcceptanceTests.swift                 (new: acceptance fixture)
Apps/projectM-iOS/UITests/HotPlugUITests.swift                       (new)
```

**Structure Decision**: extend OUT-001's coordinator in place; the pure rules go to the package that
already holds `ExternalDisplayRouting` and `OutputBlackout`.

## Complexity Tracking

None.
