# Implementation Plan: OUT-003 Independent Output Resolution

**Branch**: `feature/out-003` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/255-out-003-output-resolution/spec.md`

## Summary

Every visual already sizes its drawable as view bounds × the view's trait display scale × FR-049's
render scale. OUT-003 lets an external `VisualSlotView` override the display scale its visual reads
(`UIView.traitOverrides.displayScale` on the held visual view), so the drawable's pixel count
follows the user's choice while bounds, centre and the OUT-004 transform — the scene's coordinate
space — stay exactly as they are. A pure `ExternalOutputResolution` in `PresentationLifecycle`
resolves the scale from the slot's size in points, the screen's native scale, the choice (Native,
1080p, 720p, Custom 50…100 %) and a pixel budget (REC-014's `RecordingOutputCap.device` side and
pixel caps, passed as numbers). The coordinator pushes the choice to external slots like OUT-004's
correction (deferred while a recording holds the placement); the device slot removes any override.
`ExternalOutputSetting` persists two new keys and Settings › External Display gets a Resolution
picker plus a Custom percentage slider.

## Technical Context

**Language/Version**: Swift 6.4 (Xcode 27.2), strict concurrency; CI also builds with Xcode 26 / iOS SDK 26.5
**Primary Dependencies**: UIKit (`UIView.traitOverrides` iOS 17+, `UITraitDisplayScale`), `PresentationLifecycle`, `FrameRecording` (`RecordingOutputCap`, app side only)
**Storage**: two device-local UserDefaults values (spec Clarifications)
**Testing**: `PresentationLifecycle` package tests (host, Linux) for the arithmetic; app unit tests with a real `TextVisualHost` on an external slot (drawable, snapshot, scene-space equality); one UI test with the DEBUG fake display
**Target Platform**: iOS/iPadOS 26.5 and 27
**Performance Goals**: no per-frame cost (resolution resolves on layout only); fewer pixels when lowered
**Constraints**: public APIs only; no wall-clock assertions; unit tests ≤ 10 s, UI test ≤ 30 s; type-check budget
**Scale/Scope**: one pure type, slot/coordinator/setting changes, two Settings rows, a probe

## Constitution Check

| Principle | Check |
|---|---|
| I Public APIs only | `UIView.traitOverrides`, `UITraitCollection.displayScale`, `ProcessInfo.physicalMemory`. PASS |
| VI Modular boundaries | Arithmetic is pure Swift in `PresentationLifecycle` with the budget as plain numbers (no new package dependency); UIKit stays in the app. PASS |
| VII Real-time audio safety | Nothing touches audio. PASS |
| VIII Upstream projectM fidelity | No engine change: projectM gets a smaller viewport through the existing drawable path. PASS |
| X Evidence-based quality | Simulator cannot drive a 4K screen; a real display is `{device}` (OUT-003-T10). PASS |
| Privacy | Two local preference values, not backed up; no network. PASS |

Post-design re-check: unchanged, PASS.

## Project Structure

```text
specs/255-out-003-output-resolution/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
└── contracts/output-resolution.md

Packages/PresentationLifecycle/Sources/PresentationLifecycle/ExternalOutputResolution.swift          (new)
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/ExternalOutputResolutionTests.swift  (new)
Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift              (scale override on the held visual)
Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift  (resolution push, hold deferral, summary)
Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift        (two keys, budget)
Apps/projectM-iOS/Views/ExternalDisplaySection.swift                 (Resolution picker, Custom slider)
Apps/projectM-iOS/Coordinators/AppCoordinator+ExternalDisplay.swift  (launch wiring)
Apps/projectM-iOS/Debug/UITestExternalDisplay.swift                  (externalResolution probe)
Apps/projectM-iOS/Tests/ExternalOutputResolutionAppTests.swift       (new: acceptance)
Apps/projectM-iOS/UITests/ExternalDisplayUITests.swift               (new test)
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift (keys)
```

**Structure Decision**: arithmetic beside `ExternalOutputPlacement`; UIKit application in the slot
that already lays the visual out, so every visual kind is covered without touching any renderer.

## Complexity Tracking

None.
