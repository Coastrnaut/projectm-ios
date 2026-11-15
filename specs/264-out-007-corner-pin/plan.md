# Implementation Plan: OUT-007 Corner-Pin Warp

**Branch**: `feature/out-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A corner pin (four target points in output-relative coordinates, identity by default) is validated and
turned into a projective mapping by pure Swift in `PresentationLifecycle` (`CornerPin`, `Homography`):
Heckbert's closed-form 8-parameter unit-square-to-quad solve, a strict convexity/orientation/area/range
check (no foldover), clamped-or-refused edits, a stored-string codec and the mapping expressed as a 4 × 4
Core Animation matrix (row-vector order, perspective in m14/m24) for a layer of given size and anchor.
`VisualSlotView` (external role only) applies it as its layer's `sublayerTransform`, so everything the slot
shows (any visual: ANGLE/GLES, Metal, compositor; the bars; the calibration card; the blackout cover) goes
through one projective transform composited by Core Animation, with no extra render pass. The slot also gets
a calibration card layer (OUT-012's test-card drawing) shown while the editor is open.
`ExternalDisplayCoordinator` pushes `cornerPin` and `isCalibrating` to every external slot inside the call,
also while a recording holds the placement (the recorder taps rendered frames, never the screen).
`ExternalOutputSetting` stores one device-local key; Settings › External Display gets "Corner pin…", a
full-screen editor with draggable handles, nudge buttons, accessibility actions and Reset.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 / iOS SDK 27.2; CI Xcode 26)
**Primary Dependencies**: UIKit/Core Animation (`CATransform3D`, `sublayerTransform`), SwiftUI (editor); `PresentationLifecycle` (pure Swift, Linux-tested)
**Storage**: UserDefaults, one key `settings.externalDisplay.cornerPin` (8 numbers; absent = identity)
**Testing**: XCTest (package on host; app tests on the iOS 27.2 simulator "OUT7 iPhone 17"), one XCUITest
**Target Platform**: iOS/iPadOS 26 and 27
**Performance Goals**: no extra GPU pass; a corner change is one layer property set
**Constraints**: owner rule 7 budgets (unit ≤ 10 s, UI < 30 s); Xcode 26 type-check budget
**Scale/Scope**: one new package file, a slot/coordinator/setting extension, one editor view, DEBUG probe, key lists

## Constitution Check

- I. Public Apple APIs only: `CALayer.sublayerTransform`, `CATransform3D`, SwiftUI gestures and accessibility actions. PASS.
- IV/V. No source or capture claims. PASS.
- VI. Modular boundaries: geometry in a package; UIKit application in the app. PASS.
- VII. Real-time audio: nothing on the audio path. PASS.
- X. Evidence: pure homography/foldover tests, a layer-projection test, app tests with the external stand-in; projector check `{device}`. PASS.
- Privacy: one local preference key. PASS.

Post-design re-check: unchanged, PASS.

## Project Structure

```text
Packages/PresentationLifecycle/Sources/PresentationLifecycle/CornerPin.swift                  (new, C1)
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/CornerPinTests.swift          (new)
Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift              (cornerPin → sublayerTransform, calibration card; C2)
Apps/projectM-iOS/ExternalDisplay/CornerPinCardLayer.swift          (new: the test card as a layer; C2)
Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift  (cornerPin, isCalibrating, summary; C3)
Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift       (key, strings; C4)
Apps/projectM-iOS/Coordinators/AppCoordinator+ExternalDisplay.swift (apply the stored pin at launch; C3)
Apps/projectM-iOS/Views/ExternalDisplaySection.swift                (Corner pin… row; C4)
Apps/projectM-iOS/Views/CornerPinEditorView.swift                   (new: the editor; C4)
Apps/projectM-iOS/Debug/UITestExternalDisplay.swift                 (probe `externalCornerPin`; C5)
Apps/projectM-iOS/Tests/CornerPinAppTests.swift                     (new)
Apps/projectM-iOS/UITests/CornerPinUITests.swift                    (new)
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift, LibraryErasePolicy.swift (keys)
```

**Structure Decision**: existing app + package layout; PresentationLifecycle is already in CI's `PKGS_LIBRARY`
group. No ADR: no constitution default is overridden (the warp is a presentation property of the external
output, like OUT-004's placement).

## Complexity Tracking

None.
