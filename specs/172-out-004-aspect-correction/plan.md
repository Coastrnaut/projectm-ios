# Implementation Plan: OUT-004 Aspect Correction

**Branch**: `feature/out-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/172-out-004-aspect-correction/spec.md`

## Summary

The external display's visual is placed by `VisualSlotView` (OUT-001). OUT-004 replaces "fill the
slot" for external slots with a computed placement: a pure `ExternalOutputPlacement` in
`PresentationLifecycle` takes the slot size, the pixel aspect ratio (screen mode or override), the
source shape (display or device) and the fit mode (Fit, Fill, Stretch), and returns the view's
layout size, its horizontal scale (1/PAR) and its centre. The slot applies it as bounds, centre and
transform; its black background shows as bars and OUT-010's cover stays on top. A settings object
persists the three choices and Settings gets an External Display section.

## Technical Context

**Language/Version**: Swift 6.4 (Xcode 27.2), strict concurrency; CI also builds with Xcode 26 / iOS SDK 26.5
**Primary Dependencies**: UIKit (`UIScreen.currentMode.pixelAspectRatio`, `UIScreen.modeDidChangeNotification`), `PresentationLifecycle`
**Storage**: three device-local UserDefaults strings (spec Clarifications)
**Testing**: `PresentationLifecycle` package tests (host, Linux) for the geometry acceptance; app unit tests (snapshot of a circle grid through the slot); one UI test with the DEBUG fake display
**Target Platform**: iOS/iPadOS 26.5 and 27
**Performance Goals**: no per-frame cost (placement runs on layout only); no extra render pass
**Constraints**: public APIs only; no wall-clock assertions; unit tests ≤ 10 s, UI test ≤ 30 s; type-check budget
**Scale/Scope**: one pure type, one settings class, slot and coordinator changes, one Settings section

## Constitution Check

| Principle | Check |
|---|---|
| I Public APIs only | `UIScreenMode.pixelAspectRatio`, `UIView` bounds/center/transform. PASS |
| VI Modular boundaries | Geometry is pure Swift in `PresentationLifecycle` (Linux-tested); UIKit stays in the app. PASS |
| VII Real-time audio safety | Nothing touches audio. PASS |
| X Evidence-based quality | Simulator cannot show non-square pixels; adapter check is `{device}`. PASS |
| Privacy | Three local preference strings, not backed up; no network. PASS |

Post-design re-check: unchanged, PASS.

## Project Structure

```text
specs/172-out-004-aspect-correction/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
└── contracts/output-correction.md

Packages/PresentationLifecycle/Sources/PresentationLifecycle/ExternalOutputPlacement.swift          (new)
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/ExternalOutputPlacementTests.swift  (new: acceptance)
Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift              (apply placement, read PAR, device layout hook)
Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift  (correction, device shape, hold deferral)
Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift        (new: persisted choices)
Apps/projectM-iOS/Views/ExternalDisplaySection.swift                 (new: Settings section)
Apps/projectM-iOS/Coordinators/AppCoordinator+ExternalDisplay.swift  (wiring)
Apps/projectM-iOS/Views/SettingsView.swift, VisualizerView.swift     (one row each)
Apps/projectM-iOS/Debug/UITestExternalDisplay.swift                  (placement probe)
Apps/projectM-iOS/Tests/ExternalOutputCorrectionTests.swift          (new: slot snapshot, coordinator, persistence)
Apps/projectM-iOS/UITests/ExternalDisplayUITests.swift               (new test)
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift (keys)
```

**Structure Decision**: geometry beside `ExternalDisplayRouting`; UIKit application in the slot that
already owns the visual's frame.

## Complexity Tracking

None.
