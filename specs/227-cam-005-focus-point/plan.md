# Implementation Plan: CAM-005 Camera Focus Point

**Branch**: `feature/cam-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A double-tap on the Camera visual focuses the running camera at the camera point shown under the
finger. A pure, platform-free mapping (`CameraFocusMapping`, `CameraLayer` module) takes the touch,
the picture's on-screen rect, the drawn picture's size and rotation, the crop and the mirror, and
reuses CAM-007's `CameraPictureGeometry` (the geometry the shader draws with) to return the camera
point in AVFoundation's point-of-interest space, or nothing for Fit's bars and points outside the
rect. A focus seam (`CameraFocusConfiguring`, `CameraFocusControl`) mirrors CAM-004's exposure seam:
`AVCaptureDevice` conforms on iOS, `FakeCameraFocusDevice` for the stand-in and tests. The providers
set the point (real camera: on its session queue), reset to continuous automatic focus at the centre
before lens/position switches and on stops, and report the state read back. `CameraLayerSource`
records the last drawn picture's layout; `CameraVisualHost` maps and forwards; `AppCoordinator`
shows a ring (Reduce Motion aware), the unsupported caption, and the VoiceOver action
"Focus at centre" with its announcement; Settings › Camera gets a one-line focus note.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26)
**Primary Dependencies**: AVFoundation (`isFocusPointOfInterestSupported`, `focusPointOfInterest`, `focusMode`; iOS only), SwiftUI
**Storage**: none (session state; CAM-005-R9)
**Testing**: XCTest: `Packages/Compositor` (`CameraFocusTests`: table-driven mapping, seam, stand-in provider), app unit tests, one XCUITest file with the stand-in camera
**Target Platform**: iOS 26+; mapping and seam build on Linux (no Metal, no Foundation-only APIs beyond Swift)
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: no per-frame work besides storing three integers of the drawn picture's layout
**Constraints**: public APIs; no camera start from a tap; no new UserDefaults keys; type-check budgets
**Scale/Scope**: two new package files, provider extensions, one host method, one overlay view file, small coordinator/view edits

## Constitution Check

| Principle | Status |
|---|---|
| Public Apple APIs only | `AVCaptureDevice.isFocusPointOfInterestSupported`, `isFocusModeSupported`, `focusPointOfInterest`, `focusMode`, `lockForConfiguration`: public. |
| Privacy (no covert camera use) | Only the running, consented camera (iOS indicator and CAM-012 badge visible) is configured, only by the user's gesture or action; a tap never starts the camera; the touch point is not stored or logged. |
| Local-first, no networking | No network use. |
| Accessibility | VoiceOver action and announcement on the camera lane; Reduce Motion: ring without animation. |
| Honest evidence | Simulator proves the mapping and logic only; real focusing on D1 is `{device}` task CAM-005-T14. |
| Tests short | Package tests well under 1 s; UI test under 30 s. |

Post-design re-check: unchanged, no violations.

## Project Structure

```text
specs/227-cam-005-focus-point/     spec, plan, research, data-model, contracts/focus-point.md, quickstart, tasks
Packages/Compositor/Sources/CameraLayer/
  CameraFocusMapping.swift         NEW: pure tap → camera point mapping (platform-free)
  CameraFocus.swift                NEW: seam, state, control routine, fake device (platform-free)
  CameraPictureGeometry.swift      Double output-size initializer (the Int one calls it; no behaviour change)
  AVCameraLensInventory.swift      AVCaptureDevice: CameraFocusConfiguring (iOS)
  CameraFrameProvider.swift        protocol: focus, onFocusChange, setFocusPoint (defaults)
  CameraInputSwitch.swift          FakeCameraInput carries its fake focus device
  CameraLayerSource.swift          `drawnPicture`: the layout last drawn
  AVCameraFrameProvider.swift      set/reset on the session queue
  StubCameraFrameProvider.swift    same rules on the fake session
Packages/Compositor/Tests/CompositorTests/CameraFocusTests.swift   NEW
Apps/projectM-iOS/
  Visuals/CameraVisualHost.swift   focus(atWindowPoint:), focusAtCentre(); `-uitestCameraFocusPoint <list|none>`
  Coordinators/AppCoordinator.swift  observed `cameraFocus`, wired from the host
  Views/CameraFocusRing.swift      NEW: ring overlay, gesture modifier, coordinator extension, Settings note
  Views/VisualizerView.swift       gesture modifier on the tap area, ring layer
  Views/SettingsView.swift         focus note after the exposure row
  Tests/CameraFocusAppTests.swift  NEW
  UITests/CameraFocusUITests.swift NEW
```

**Structure Decision**: follow CAM-004's split (platform-free seam in `CameraLayer`, providers, host,
one app view file with its coordinator extension).
