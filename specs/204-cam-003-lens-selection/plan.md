# Implementation Plan: CAM-003 Camera Lens Selection

**Branch**: `feature/cam-003` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/204-cam-003-lens-selection/spec.md`

## Summary

The back camera gets a lens choice. `CameraLens` (wide, ultraWide, telephoto) and a
`CameraLensInventory` protocol live in the `CameraLayer` target of `Packages/Compositor`; the iOS
implementation `AVCameraLensInventory` lists the back position's physical lenses with
`AVCaptureDevice.DiscoverySession` (`.builtInUltraWideCamera`, `.builtInWideAngleCamera`,
`.builtInTelephotoCamera`), and `FixedCameraLensInventory` is the stand-in. A lens switch on a running
session goes through one generic, platform-free routine, `CameraInputSwitch.replace(...)`, written
against a small `CameraInputConfiguring` protocol that `AVCaptureSession` conforms to and that a fake
session (`FakeCameraCaptureSession`) also implements: create the new input first (failure → nothing
touched), then inside `beginConfiguration`/`commitConfiguration` remove the old input, add the new
one, and on refusal re-add the old one, else the wide lens; the outcome is reported. The real
provider runs it on its session queue; the stand-in provider runs it on its fake session, so the same
code is tested on the Mac. The app stores the lens in `settings.camera.lens`, resolves it against the
inventory (missing → wide), and shows a segmented "Lens" row in Settings › Camera only for Back with at
least two lenses.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: AVFoundation (iOS only, already used by CAM-001). No new dependency.

**Storage**: One UserDefaults key, `settings.camera.lens` (`wide`/`ultraWide`/`telephoto`; else wide).

**Testing**: XCTest. `swift test --package-path Packages/Compositor --filter CameraLens` on the
macOS host (switch routine, fake session, stand-in provider); app unit tests and one UI test file on
the agent's simulator "CAM3 iPhone 17" (iOS 27.2) with the stand-in camera.

**Target Platform**: iOS/iPadOS 26.0+.

**Project Type**: iOS app with SwiftPM packages.

**Performance Goals**: A lens switch costs one session reconfiguration; nothing per frame.

**Constraints**: No camera start, prompt or capture from listing (R3); never a crash, never a session
left without input when any lens can be added (R7); type-check budget (300 ms per function, 200 ms
per expression).

**Scale/Scope**: 3 lens kinds, 1 setting, 1 Settings row.

## Constitution Check

| Principle | Status |
|---|---|
| Public Apple APIs only | `AVCaptureDevice.DiscoverySession`, `AVCaptureDeviceInput`, `AVCaptureSession` configuration: public. |
| Privacy (sensor needs spec and privacy review) | Spec "Privacy review": discovery opens no camera; capture only with consent and visible indication (iOS indicator, CAM-012 badge), unchanged. |
| Local-first, no networking | No network use. |
| Honest evidence | Simulator results prove logic only; real lens switching is a `{device}` task on D1/D2. |
| Tests short | Package tests under 1 s each; UI tests under 30 s. |

## Project Structure

```text
Packages/Compositor/Sources/CameraLayer/
  CameraLens.swift                 # CameraLens, CameraLensInventory, FixedCameraLensInventory, resolve
  CameraInputSwitch.swift          # CameraInputConfiguring, CameraInputSwitch, FakeCameraCaptureSession
  AVCameraLensInventory.swift      # iOS: DiscoverySession; AVCaptureSession: CameraInputConfiguring
  AVCameraFrameProvider.swift      # lens, availableLenses, selectLens (switch on the session queue)
  CameraFrameProvider.swift        # protocol: lens, selectLens (defaults: wide, no-op)
  StubCameraFrameProvider.swift    # inventory, failing lenses, fake session
Packages/Compositor/Tests/CompositorTests/CameraLensTests.swift
Apps/projectM-iOS/Coordinators/AppSettings.swift      # settings.camera.lens
Apps/projectM-iOS/Coordinators/AppCoordinator.swift   # inventory, forward the lens
Apps/projectM-iOS/Visuals/CameraVisualHost.swift      # cameraLens, stand-in args
Apps/projectM-iOS/Views/SettingsView.swift            # Lens row in cameraSection
Apps/projectM-iOS/Tests/CameraLensTests.swift
Apps/projectM-iOS/UITests/CameraLensUITests.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py
```

**Structure Decision**: Everything camera-specific stays in `CameraLayer` next to CAM-001/002/013;
the switch routine is platform-free so the acceptance runs on the Mac host.
