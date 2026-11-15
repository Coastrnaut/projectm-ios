# Implementation Plan: CAM-010 Hand Pose Modulation

**Branch**: `feature/cam-010` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

An opt-in "Hand tracking" switch in Settings › Camera, built on CAM-009's template. CAM-009's face analyzer becomes a
generic `CameraFeatureAnalyzer<Tracker>` (gate first, lazy detector, 15 Hz schedule, generation drop, failure stop);
face and hand are two instances of it. The camera's one `pictureAnalyzer` slot gets a fixed `CameraPictureAnalyzerGroup`
(CameraLayer) that offers each picture to both. A Vision `VNDetectHumanHandPoseRequest` detector (max 2 hands) copies
seven joints per hand into a `HandPoseFrame`; `HandFeatureTracker` (ParameterGraph, Linux) turns it into nine smoothed
0…1 scalars with a hold-then-step one-pole, so a recorded pose sequence is deterministic at shared times. The scalars
are sources `audio.hand.<feature>`. Consent uses one shared `CameraAnalysisConsent` model for face and hand.
To close CAM-009-D8's gap, the Camera visual gains a `CameraVisualModulation`: the native visuals' `AudioFeatureModulator`
over the visual catalog, loaded with the scene's bindings, advanced on the Camera visual's frame clock with band, face
and hand values, and applied to the circular spectrum layer it draws (inner radius, gap).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26 and Linux)
**Primary Dependencies**: Vision (`VNDetectHumanHandPoseRequest`, app only), CoreVideo; no package dependency added
**Storage**: two UserDefaults keys `settings.camera.handTracking`, `settings.camera.handTrackingConsent` (excluded from backup); values memory only
**Testing**: XCTest: ParameterGraph `HandFeatureTrackerTests` (incl. the recorded-pose determinism acceptance through the modulator), CompositorTests `CameraPictureAnalyzerGroupTests`, app `HandTrackingAppTests`, UI `HandTrackingConsentUITests`; the existing `FaceTrackingAppTests` guard the refactor
**Target Platform**: iOS 26+; plain parts on Linux
**Performance Goals**: ≤ 15 hand analyses/s, one in flight, own utility queue; per-frame camera modulation allocates nothing (struct reads, preallocated modulator)
**Constraints**: public APIs; no network; no new permission or Info.plist key; consent before any request; type-check budget; small edits in AppCoordinator, SettingsView, VisualizerView
**Scale/Scope**: 9 sources, 1 switch + sheet, 1 generic analyzer (2 instances), 1 coordinator, 1 camera modulation

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Vision hand pose, CoreVideo: public. |
| VI Modular boundaries | Normalisation, smoothing, gate in ParameterGraph; CameraLayer gains only a fan-out of its own protocol; Vision only in the app behind `HandPoseDetecting`. |
| Privacy | Never starts capture; analysis only after its own consent and camera authorization; on-device; memory only; no logs of values; privacy policy updated; ADR-0087 (extends ADR-0081). |
| VII Real-time safety | Analysis off the camera and render threads; the render thread reads structs under a short lock; the camera thread never waits. |
| X Evidence | Simulator proves logic with stub/recorded detectors; real hands, indicator and frame rate on D1 are `{device}` CAM-010-T17. |
| Short tests | Package tests < 1 s each; app tests < 10 s; one UI test < 30 s. |

Post-design re-check: no violations.

## Project Structure

```text
specs/276-cam-010-hand-pose-modulation/   spec, plan, research, data-model, contracts/hand-sources.md, quickstart, tasks
docs/adr/0087-on-device-hand-pose.md                                         NEW
docs/privacy-policy.md                                                       hand tracking paragraph
Packages/ParameterGraph/Sources/ParameterGraph/HandFeatureTracker.swift     NEW: feature, values, joints, frame, normaliser, tracker
Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift     `.hand(HandFeature)`, `AudioFeatureFrame.hand`
Packages/ParameterGraph/Sources/ParameterExpression/*                        refuse / unreachable
Packages/ParameterGraph/Tests/ParameterGraphTests/HandFeatureTrackerTests.swift   NEW
Packages/Compositor/Sources/CameraLayer/CameraFrameProvider.swift           `CameraPictureAnalyzerGroup`
Packages/Compositor/Tests/CompositorTests/CameraPictureAnalyzerTests.swift  group test
Apps/projectM-iOS/Coordinators/CameraFeatureAnalyzer.swift                   NEW: generic analyzer, shared consent model
Apps/projectM-iOS/Coordinators/FaceLandmarkAnalyzer.swift                    face detector + `FaceLandmarkAnalyzer` = generic
Apps/projectM-iOS/Coordinators/FaceTrackingCoordinator.swift                 uses the shared consent model
Apps/projectM-iOS/Coordinators/HandPoseAnalyzer.swift                        NEW: detector protocol, Vision, stub, recorded
Apps/projectM-iOS/Coordinators/HandTrackingCoordinator.swift                 NEW
Apps/projectM-iOS/Coordinators/AppCoordinator+HandTracking.swift             NEW: wiring, badge, overlay, camera analysis group, camera modulation
Apps/projectM-iOS/Visuals/CameraVisualHost+Modulation.swift                  NEW: `CameraVisualModulation`
Apps/projectM-iOS/Visuals/CameraVisualHost.swift, +PersonMask.swift          one stored property, one frame call, rate for every analyzer
Apps/projectM-iOS/Views/CameraHandTrackingRow.swift                          NEW
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift, AppCoordinator.swift, ParameterInspectorModel.swift,
  Views/SettingsView.swift, Views/VisualizerView.swift, Views/CameraIndicator.swift   small edits
Apps/projectM-iOS/Tests/HandTrackingAppTests.swift, UITests/HandTrackingConsentUITests.swift   NEW
scripts/run_device_tests.py, LibrarySettings.swift, LibraryErasePolicy.swift, LibraryBackupAppTests.swift   keys
```

**Structure Decision**: share CAM-009's analyzer and consent code rather than copy it; keep Vision in the app.

## Complexity Tracking

None.
