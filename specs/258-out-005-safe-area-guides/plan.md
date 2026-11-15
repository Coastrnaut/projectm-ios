# Implementation Plan: OUT-005 Safe-Area Guides

**Branch**: `feature/out-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A device-only SwiftUI overlay draws action-safe (93 %) and title-safe (90 %) outlines, and an
optional centre cross, over the visualizer's visual area. The geometry is pure Swift in
`PresentationLifecycle` (beside OUT-004's placement math). The overlay sits in the visualizer's
backdrop right above the visual, scaled with it by UIX-007's `.splitOutputScaled()`, and never in
the visual's own view, so external output, recordings, Save Frame and offline export cannot see it
(the same isolation UIX-013's HUD proves). With an external display showing the visual, the output
frame is the display's physical shape (OUT-004's resolved pixel aspect). A preference object stores
four keys; Settings › Performance gets a section.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 / iOS SDK 27.2; CI Xcode 26)
**Primary Dependencies**: SwiftUI, UIKit (app); `PresentationLifecycle` (pure Swift, Linux-tested)
**Storage**: UserDefaults (four preference keys)
**Testing**: XCTest (package on host and Linux; app tests on the iOS 27.2 simulator "OUT5 iPhone 17"), one XCUITest
**Target Platform**: iOS/iPadOS 26 and 27
**Performance Goals**: no change to the visual's frame rate; the overlay is static vector strokes redrawn only on layout or setting change
**Constraints**: owner rule 7 budgets (unit ≤ 10 s, UI < 30 s); Xcode 26 type-check budget (300 ms bodies, 200 ms expressions)
**Scale/Scope**: size S: one pure file, one setting, one overlay view, one Settings section, small edits to VisualizerView, SettingsView, AppCoordinator, ExternalDisplayCoordinator

## Constitution Check

- I. Public Apple APIs only: SwiftUI shapes, UserDefaults. PASS.
- IV/V. No source or capture claims touched. PASS.
- VI. Modular boundaries: pure geometry in a package; UI in the app. PASS.
- VII. Real-time audio: nothing on the audio path. PASS.
- X. Evidence: pixel-identity acceptance tests; device check left `{device}`. PASS.
- Privacy: four local preference keys, no data leaves the device. PASS.

## Project Structure

```text
Packages/PresentationLifecycle/Sources/PresentationLifecycle/SafeAreaGuides.swift      (new, C1)
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/SafeAreaGuidesTests.swift (new)
Apps/projectM-iOS/Coordinators/SafeAreaGuideSetting.swift                            (new, C3)
Apps/projectM-iOS/Views/SafeAreaGuidesOverlay.swift                                  (new, C2, C4: overlay, Settings section, DEBUG probe)
Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift                   (externalScreenAspect)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                                  (lazy setting)
Apps/projectM-iOS/Views/VisualizerView.swift                                         (backdrop layer, Settings argument)
Apps/projectM-iOS/Views/SettingsView.swift                                           (one row in performanceSection)
Apps/projectM-iOS/Tests/SafeAreaGuidesAppTests.swift                                 (new: acceptance, persistence)
Apps/projectM-iOS/UITests/SafeAreaGuidesUITests.swift                                (new)
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift, Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift (keys)
```

**Structure Decision**: existing app + package layout; no new package (PresentationLifecycle is already in the CI `PKGS_LIBRARY` group).

## Complexity Tracking

None.
