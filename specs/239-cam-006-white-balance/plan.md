# Implementation Plan: CAM-006 Camera White Balance

**Branch**: `feature/cam-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Add a "Lock white balance" switch to Settings › Camera, built exactly like CAM-004's exposure lock.
A platform-free seam in the `CameraLayer` module (`CameraWhiteBalanceConfiguring`,
`CameraWhiteBalanceControl`) does every lock, release and read-back inside one
`lockForConfiguration`/`unlockForConfiguration` pair. A lock at given values passes only gains made
valid by `CameraWhiteBalanceGains.validated(maximum:)` (each channel clamped into 1…maximum; non-finite
values refuse the lock). `AVCaptureDevice` conforms on iOS and `FakeCameraWhiteBalanceDevice`
implements it for the stand-in camera and tests; the fake counts configurations, changes outside a
configuration and invalid gains applied (all must stay 0 where expected). The providers expose
`whiteBalance`, `onWhiteBalanceChange` and `setWhiteBalanceLocked(_:)`, release the lock wherever
CAM-004 releases exposure (lens/position switch, every stop and failure) and keep it across
interruptions. `CameraVisualHost` forwards it, `AppCoordinator` mirrors it in one observed property,
and `CameraWhiteBalanceRow` shows the switch.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26)
**Primary Dependencies**: AVFoundation (`AVCaptureDevice` white balance API, iOS only), SwiftUI
**Storage**: none (session state; CAM-006-R10)
**Testing**: XCTest: `Packages/Compositor` (`CameraWhiteBalanceTests`), app unit tests, one XCUITest file with the stand-in camera
**Target Platform**: iOS 26+ (iPhone, iPad); seam builds on Linux (Foundation only)
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: no per-frame work; a change is one device configuration on the session queue
**Constraints**: public APIs; no camera start from the row; no new UserDefaults keys; never an invalid gain
**Scale/Scope**: one seam file, provider edits, one row view, small host/coordinator/settings edits

## Constitution Check

| Principle | Status |
|---|---|
| Public Apple APIs only | `isWhiteBalanceModeSupported`, `whiteBalanceMode`, `deviceWhiteBalanceGains`, `maxWhiteBalanceGain`, `isLockingWhiteBalanceWithCustomDeviceGainsSupported`, `setWhiteBalanceModeLocked(with:completionHandler:)`, `lockForConfiguration`/`unlockForConfiguration`: public. |
| Privacy (sensor needs spec and privacy review) | Spec "Privacy review": no new sensor; only the running, consented camera is configured; nothing stored. |
| Local-first, no networking | No network use. |
| Photosensitivity | A lock holds colors steady; it cannot add flashing. |
| Honest evidence | Simulator results prove logic only; a real lock on D1 is the `{device}` task CAM-006-T09. |
| Tests short | Package tests well under 1 s each; one UI test file, each test under 30 s. |

Post-design re-check: unchanged, no violations.

## Project Structure

```text
specs/239-cam-006-white-balance/   spec, plan, research, data-model, contracts/white-balance-lock.md, quickstart, tasks
Packages/Compositor/Sources/CameraLayer/
  CameraWhiteBalance.swift         NEW: gains, state, seam, control routine, fake device (platform-free)
  AVCameraLensInventory.swift      AVCaptureDevice: CameraWhiteBalanceConfiguring (iOS)
  CameraFrameProvider.swift        protocol: whiteBalance, onWhiteBalanceChange, setWhiteBalanceLocked (defaults)
  CameraInputSwitch.swift          FakeCameraInput/session carry a fake white balance device per camera
  AVCameraFrameProvider.swift      lock/release on the session queue; release with exposure; read back with exposure
  StubCameraFrameProvider.swift    same rules on the fake session
Packages/Compositor/Tests/CompositorTests/CameraWhiteBalanceTests.swift   NEW
Apps/projectM-iOS/
  Visuals/CameraVisualHost.swift   forwards white balance; `-uitestCameraWhiteBalanceLock <list|none>`
  Coordinators/AppCoordinator.swift  observed `cameraWhiteBalance`, wired from the host
  Views/CameraWhiteBalanceRow.swift  NEW: row + coordinator extension
  Views/SettingsView.swift         one optional row after Lock exposure; footer sentence
  Views/VisualizerView.swift       passes the row's choice
  Tests/CameraWhiteBalanceAppTests.swift   NEW
  UITests/CameraWhiteBalanceUITests.swift  NEW
```

**Structure Decision**: follow CAM-004 file for file.
