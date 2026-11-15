# Implementation Plan: OUT-006 Output Mirroring Toggle

**Branch**: `feature/out-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A per-output mode, Same scene (default) or Clean output, decides which layer classes reach the
external display. The rule is pure Swift in `PresentationLifecycle` (`ExternalOutputMode`,
`OutputLayerRouting`, beside OUT-001's routing). `ExternalDisplayCoordinator` evaluates it in
`place()` and on every mode change (the visual's effective target × the mode) and reports whether
scene overlays are routed to the slot holding the visual. `AppCoordinator` wires that to MED-010's
`LogoCoordinator`, which pushes an effective placement (opacity 0 while routed away) to every live
logo layer without touching the stored placement. The visual never moves for a mode change and
nothing on the audio path is touched: the one `CaptureManager`, its normalized output and analysis
tap stay the same objects. `ExternalOutputSetting` stores one device-local key and Settings ›
External Display gets an Output picker.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 / iOS SDK 27.2; CI Xcode 26)
**Primary Dependencies**: SwiftUI, UIKit (app); `PresentationLifecycle` (pure Swift, Linux-tested); MED-010 `LogoLayerSource` (unchanged)
**Storage**: UserDefaults, one key `settings.externalDisplay.outputMode` (`sameScene`, `clean`)
**Testing**: XCTest (package on host; app tests on the iOS 27.2 simulator "OUT6 iPhone 17"), one XCUITest
**Target Platform**: iOS/iPadOS 26 and 27
**Performance Goals**: no extra render, no extra frame work; a mode change is a few property sets
**Constraints**: owner rule 7 budgets (unit ≤ 10 s, UI < 30 s); Xcode 26 type-check budget
**Scale/Scope**: one pure file, edits to ExternalDisplayCoordinator, LogoCoordinator, ExternalOutputSetting, ExternalDisplaySection, AppCoordinator+ExternalDisplay, the DEBUG fake display panel; key lists

## Constitution Check

- I. Public Apple APIs only: UserDefaults, SwiftUI Picker. PASS.
- IV/V. No source or capture claims. PASS.
- VI. Modular boundaries: routing rule in a package; wiring in the app. PASS.
- VII. Real-time audio: nothing on the audio path; the acceptance test asserts the pipeline is untouched. PASS.
- X. Evidence: app acceptance test with the external stand-in; device check `{device}`. PASS.
- Privacy: one local preference key. PASS.

Post-design re-check: unchanged, PASS.

## Project Structure

```text
Packages/PresentationLifecycle/Sources/PresentationLifecycle/ExternalOutputMode.swift          (new, C1)
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/ExternalOutputModeTests.swift  (new)
Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift   (outputMode, routesSceneOverlays, callback; C2)
Apps/projectM-iOS/Coordinators/LogoCoordinator.swift                 (outputSuppressed, effective placement; C3)
Apps/projectM-iOS/Coordinators/AppCoordinator+ExternalDisplay.swift  (wiring; C2)
Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift        (key, strings; C4)
Apps/projectM-iOS/Views/ExternalDisplaySection.swift                 (Output picker; C4)
Apps/projectM-iOS/Debug/UITestExternalDisplay.swift                  (probe `externalOutputMode`; C5)
Apps/projectM-iOS/Tests/ExternalOutputModeAppTests.swift              (new: acceptance, persistence)
Apps/projectM-iOS/UITests/ExternalOutputModeUITests.swift             (new)
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift, LibraryErasePolicy.swift (keys)
```

**Structure Decision**: existing app + package layout; PresentationLifecycle is already in CI's `PKGS_LIBRARY` group. No ADR: no default is overridden (OUT-001-R3's single render is kept).

## Complexity Tracking

None.
