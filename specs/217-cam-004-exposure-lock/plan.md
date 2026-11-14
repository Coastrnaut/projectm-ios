# Implementation Plan: CAM-004 Camera Exposure Lock

**Branch**: `feature/cam-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Add a "Lock exposure" switch to Settings › Camera. A platform-free exposure seam in the
`CameraLayer` module (`CameraExposureConfiguring`, `CameraExposureControl`) does every lock, release
and read-back inside one `lockForConfiguration`/`unlockForConfiguration` pair; `AVCaptureDevice`
conforms to it on iOS and `FakeCameraExposureDevice` implements it for the stand-in camera and
tests, so the code that locks the real camera is the code the Mac tests run (as CAM-003's input
switch). The providers (`AVCameraFrameProvider`, `StubCameraFrameProvider`) expose the camera's
exposure state, change it on request (real camera: on its session queue), release it before a
lens/position switch and on every stop, and report each change. `CameraVisualHost` forwards it,
`AppCoordinator` mirrors it in one observed property, and `CameraExposureRow` shows the switch,
disabled with an explanation when the camera cannot lock or is not running.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26)
**Primary Dependencies**: AVFoundation (`AVCaptureDevice` exposure API, iOS only), SwiftUI
**Storage**: none (session state; CAM-004-R8)
**Testing**: XCTest: `Packages/Compositor` (`CameraExposureTests`), app unit tests, one XCUITest file with the stand-in camera
**Target Platform**: iOS 26+ (iPhone, iPad); seam builds on Linux (Foundation only)
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: no per-frame work; a lock is one device configuration on the session queue
**Constraints**: public APIs; no camera start from the row; no new UserDefaults keys
**Scale/Scope**: one seam file, two provider extensions, one row view, small host/coordinator edits

## Constitution Check

| Principle | Status |
|---|---|
| Public Apple APIs only | `AVCaptureDevice.isExposureModeSupported`, `exposureMode`, `lockForConfiguration`/`unlockForConfiguration`: public. |
| Privacy (sensor needs spec and privacy review) | Spec "Privacy review": no new sensor; only the running, consented camera (iOS indicator and CAM-012 badge) is configured; no covert use; nothing stored. |
| Local-first, no networking | No network use. |
| Photosensitivity | No manual shutter/ISO (Clarifications); locking cannot add flashing; Reduce flashing still applies to the composite. |
| Honest evidence | Simulator results prove logic only; a real lock on D1 is the `{device}` task CAM-004-T08. |
| Tests short | Package tests under 1 s each; one UI test under 30 s. |

Post-design re-check: unchanged, no violations.

## Project Structure

```text
specs/217-cam-004-exposure-lock/   spec, plan, research, data-model, contracts/exposure-lock.md, quickstart, tasks
Packages/Compositor/Sources/CameraLayer/
  CameraExposure.swift             NEW: seam, state, control routine, fake device (platform-free)
  AVCameraLensInventory.swift      AVCaptureDevice: CameraExposureConfiguring (iOS)
  CameraFrameProvider.swift        protocol: exposure, onExposureChange, setExposureLocked (defaults)
  CameraInputSwitch.swift          FakeCameraInput carries its fake exposure device
  AVCameraFrameProvider.swift      lock/release on the session queue; release before switches and on stop
  StubCameraFrameProvider.swift    same rules on the fake session
Packages/Compositor/Tests/CompositorTests/CameraExposureTests.swift   NEW
Apps/projectM-iOS/
  Visuals/CameraVisualHost.swift   forwards exposure; `-uitestCameraExposureLock <list|none>`
  Coordinators/AppCoordinator.swift  observed `cameraExposure`, wired from the host
  Views/CameraExposureRow.swift    NEW: row + coordinator extension
  Views/SettingsView.swift         one optional row after the Lens row
  Views/VisualizerView.swift       passes the row's choice
  Tests/CameraExposureAppTests.swift   NEW
  UITests/CameraExposureUITests.swift  NEW
```

**Structure Decision**: follow CAM-003's split (platform-free seam in `CameraLayer`, providers,
host, one row file with its coordinator extension).
