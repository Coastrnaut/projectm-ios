# Implementation Plan: CAM-009 Face Landmark Emitters

**Branch**: `feature/cam-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

An opt-in "Face tracking" switch in Settings › Camera. Behind a stored consent (explanation sheet) and the existing
camera permission, a `FaceLandmarkAnalyzer` receives the Camera visual's own pictures through a new generic provider
hook (`CameraPictureAnalyzing`, beside CAM-008's masker), runs Vision face landmarks at most 15 times a second on a
utility queue, and turns the largest face into eight smoothed 0…1 scalars (`FaceFeatureTracker`, ParameterGraph,
Linux). The scalars are bindable sources `audio.face.<feature>`, read by the native spectrum host like CAM-011's
motion sources. Nothing face-related is stored, logged, exported or sent; the detector is created lazily and only
after the gate opens, so a spy factory proves the gate.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26 and Linux)
**Primary Dependencies**: Vision (`VNDetectFaceLandmarksRequest`, app target only), CoreVideo; no package dependency added
**Storage**: two UserDefaults keys `settings.camera.faceTracking`, `settings.camera.faceTrackingConsent` (excluded from backup); values memory only
**Testing**: XCTest: ParameterGraph `FaceFeatureTrackerTests` (host + Linux shape), app `FaceTrackingAppTests`, one UI test file `FaceTrackingConsentUITests`
**Target Platform**: iOS 26+; plain parts on Linux
**Performance Goals**: ≤ 15 analyses/s, one in flight, never on main or render thread; per-frame read is a struct copy under a short lock
**Constraints**: public APIs; no network; no new permission or Info.plist key; consent before any request; type-check budget
**Scale/Scope**: 8 sources, 1 switch + sheet, 1 analyzer, 1 coordinator

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Vision face landmarks, CoreVideo: public. |
| VI Modular boundaries | Normalisation, smoothing, schedule, gate in ParameterGraph (pure Swift); camera package gains only a protocol hook; Vision only in the app behind `FaceLandmarkDetecting`. |
| Privacy | Capture is never started by this feature; analysis only after explicit consent and system camera authorization; on-device; memory only; no logs of values; privacy policy updated; ADR-0081. |
| VII Real-time safety | Analysis on a utility queue; the render thread reads a struct; the camera thread never waits. |
| X Evidence | Simulator proves logic with a stub detector; real faces, the indicator and frame rate on D1 are `{device}` CAM-009-T16. |
| Short tests | Package tests < 1 s; app tests < 10 s; one UI test < 30 s. |

Post-design re-check: no violations.

## Project Structure

```text
specs/270-cam-009-face-landmark-emitters/   spec, plan, research, data-model, contracts/face-sources.md, quickstart, tasks
docs/adr/0081-on-device-face-landmarks.md                                   NEW
docs/privacy-policy.md                                                       face tracking paragraph
Packages/ParameterGraph/Sources/ParameterGraph/FaceFeatureTracker.swift     NEW: feature, values, sample, normaliser, tracker, schedule, gate
Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift     `.face(FaceFeature)`, `AudioFeatureFrame.face`
Packages/ParameterGraph/Sources/ParameterExpression/ExpressionCatalog.swift, ExpressionCompiler.swift   refuse / unreachable
Packages/ParameterGraph/Tests/ParameterGraphTests/FaceFeatureTrackerTests.swift   NEW
Packages/Compositor/Sources/CameraLayer/CameraFrameProvider.swift           `CameraPictureAnalyzing`, `pictureAnalyzer` hook
Packages/Compositor/Sources/CameraLayer/AVCameraFrameProvider.swift, StubCameraFrameProvider.swift, CameraLayerSource.swift   offer / reset
Apps/projectM-iOS/Coordinators/FaceLandmarkAnalyzer.swift                    NEW: detector protocol, Vision detector, stub, analyzer
Apps/projectM-iOS/Coordinators/FaceTrackingCoordinator.swift                 NEW: switch, consent, permission, gate, status
Apps/projectM-iOS/Views/CameraFaceTrackingRow.swift                          NEW: switch, note, consent sheet
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift                           `faceValues`, `usesFace`
Apps/projectM-iOS/Coordinators/AppCoordinator.swift, ParameterInspectorModel.swift, Views/SettingsView.swift,
  Views/VisualizerView.swift, Views/CameraIndicator.swift                    small edits
Apps/projectM-iOS/Tests/FaceTrackingAppTests.swift, UITests/FaceTrackingConsentUITests.swift   NEW
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift, Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift   keys
```

**Structure Decision**: the analyzer lives in the app (as CAM-011's sensor) so the camera package gains no Vision
face code and no ParameterGraph dependency; the provider hook is generic so CAM-008 and CAM-009 share the frame path.

## Complexity Tracking

None.
