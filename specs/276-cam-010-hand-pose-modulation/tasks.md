# Tasks: CAM-010 Hand Pose Modulation

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/hand-sources.md](contracts/hand-sources.md), [quickstart.md](quickstart.md)

Tests are requested by the spec (acceptance: recorded synthetic pose frames, consent gate, no data leaves, app and UI tests).
`{device}` tasks need a physical device and stay open.

## Phase 1: Setup

- [ ] CAM-010-T01 Create the spec directory artifacts and the feature pointer in `specs/276-cam-010-hand-pose-modulation/`

## Phase 2: Foundational (blocks every story)

- [ ] CAM-010-T02 [P] Add `HandFeature`, `HandFeatureValues` (neutral: present 0, x 0.5, y 0.5, pinch 0, open 0, size 0, second 0, secondX 0.5, secondY 0.5), `HandJointPoint`, `HandObservationSample`, `HandPoseFrame`, `HandFeatureNormalizer` (confidence floor 0.3, ≥ 6 confident joints, palm ≥ 0.01, pinch/open/size as spec Clarifications) and the hold-then-step `HandFeatureTracker` in `Packages/ParameterGraph/Sources/ParameterGraph/HandFeatureTracker.swift`
- [ ] CAM-010-T03 Add `.hand(HandFeature)` (`audio.hand.` prefix, parse, value, `AudioFeatureFrame.hand`) in `Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift`; refuse it in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionCatalog.swift` and `ExpressionCompiler.swift`
- [ ] CAM-010-T04 [P] Add `CameraPictureAnalyzerGroup` in `Packages/Compositor/Sources/CameraLayer/CameraFrameProvider.swift` and its test in `Packages/Compositor/Tests/CompositorTests/CameraPictureAnalyzerTests.swift`
- [ ] CAM-010-T05 Extract CAM-009's analyzer into the generic `CameraFeatureAnalyzer<Tracker>` and the shared `CameraAnalysisConsent` model in `Apps/projectM-iOS/Coordinators/CameraFeatureAnalyzer.swift`; keep `FaceLandmarkAnalyzer` (typealias + convenience init) in `FaceLandmarkAnalyzer.swift` and move `FaceTrackingCoordinator` onto the consent model; `FaceTrackingAppTests` unchanged must pass

## Phase 3: User Story 1 — Opt in before any hand is analysed (P1)

**Independent test**: zero hand detectors and detections before consent; detections after consent and access; flat after off.

- [ ] CAM-010-T06 [US1] Add `HandPoseDetecting`, `VisionHandPoseDetector` (`VNDetectHumanHandPoseRequest`, `maximumHandCount = 2`, seven joints, upright aspect), `StubHandPoseDetector`, `RecordedHandPoseDetector` and `HandPoseAnalyzer` in `Apps/projectM-iOS/Coordinators/HandPoseAnalyzer.swift`
- [ ] CAM-010-T07 [US1] Add `HandTrackingCoordinator` (keys `settings.camera.handTracking`, `settings.camera.handTrackingConsent`; notes "Hand tracking needs camera access." / "Hand tracking isn't available right now."; announcement "Hand tracking on") in `Apps/projectM-iOS/Coordinators/HandTrackingCoordinator.swift`
- [ ] CAM-010-T08 [US1] Add `CameraHandTrackingRow` and `HandTrackingConsentSheet` in `Apps/projectM-iOS/Views/CameraHandTrackingRow.swift`; show it in `SettingsView.swift`'s camera section and pass it from `VisualizerView.swift`
- [ ] CAM-010-T09 [US1] Wire the coordinator, the camera analysis group, mirroring, permission refresh, badge ("Hand tracking") and overlay lines in `Apps/projectM-iOS/Coordinators/AppCoordinator+HandTracking.swift`, `AppCoordinator.swift`, `Views/CameraIndicator.swift`, `Views/VisualizerView.swift`; analysis rate for every analyzer in `Visuals/CameraVisualHost+PersonMask.swift`
- [ ] CAM-010-T10 [US1] Keys: `scripts/run_device_tests.py` ALLOWED_KEYS, `LibrarySettings.swift` excluded keys, `LibraryErasePolicy.swift`, the UI-test reset in `AppCoordinator.swift`, `Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift`
- [ ] CAM-010-T11 [US1] Consent-gate app test (copy of CAM-009's) in `Apps/projectM-iOS/Tests/HandTrackingAppTests.swift`
- [ ] CAM-010-T12 [US1] UI test: sheet before activation, Cancel leaves it off, Confirm turns it on, in `Apps/projectM-iOS/UITests/HandTrackingConsentUITests.swift`

## Phase 4: User Story 2 — Hands drive the scene (P1)

**Independent test**: a recorded pose fixture drives a bound parameter deterministically; the Camera visual applies bindings.

- [ ] CAM-010-T13 [P] [US2] Package tests: normalisation (centred, pinch, fist, extreme, degenerate, non-finite, low confidence), smoothing, and the recorded-pose determinism acceptance through `AudioFeatureModulator` (two runs identical, expected values at sample times within 0.001, jittered cadence equal at shared times within 1e-9) in `Packages/ParameterGraph/Tests/ParameterGraphTests/HandFeatureTrackerTests.swift`
- [ ] CAM-010-T14 [US2] Camera visual modulation (`CameraVisualModulation`: catalog modulator, load, resolve inner radius and gap, face and hand readers) in `Apps/projectM-iOS/Visuals/CameraVisualHost+Modulation.swift`; one stored property and one frame call in `CameraVisualHost.swift`; load on creation and on matrix edits in `AppCoordinator+HandTracking.swift`, `AppCoordinator.swift`, `AppCoordinator+ModulationMatrix.swift`; native host reads hand values (`NativeSpectrumHost.swift`); inspector names in `ParameterInspectorModel.swift`; DEBUG seed `-uitestBindCameraRadiusToPinch` (binds `audio.hand.pinch` to `visual.circularSpectrum.innerRadius` for the device check T17)
- [ ] CAM-010-T15 [US2] App tests: recorded poses through `HandPoseAnalyzer` and `CameraVisualModulation` (deterministic radius), face and hand bindings move the Camera visual's spectrum inner radius in a stand-in-camera host, in `Apps/projectM-iOS/Tests/HandTrackingAppTests.swift`

## Phase 5: User Story 3 — Nothing leaves the device (P1)

- [ ] CAM-010-T16 [US3] App tests: container snapshot unchanged, scene and performance report free of hand tokens, source scan of the hand files, in `Apps/projectM-iOS/Tests/HandTrackingAppTests.swift`

## Phase 6: Polish

- [ ] CAM-010-T17 {device} D1: real hands drive the bound inner radius (DEBUG `-uitestBindCameraRadiusToPinch`), the badge and iOS's camera indicator show, frame rate with face and hand tracking on recorded
- [ ] CAM-010-T18 ADR `docs/adr/0087-on-device-hand-pose.md`, `docs/adr/README.md`, privacy policy section in `docs/privacy-policy.md`, CAM-009's limitation note updated in `specs/270-cam-009-face-landmark-emitters/spec.md` Assumptions
- [ ] CAM-010-T19 Repo checks, the Linux shape of `HandFeatureTracker.swift` (Foundation-free, as `FaceFeatureTracker.swift`; CAM-010-R15), type-check budget, network symbols and privacy manifest on the built app, `SettingsTests` and `LibraryBackupAppTests`

## Dependencies

T02-T05 before all stories. US1 (T06-T12) before US2's app test T15 (needs the analyzer); T13 only needs T02-T03.
US3 (T16) needs T06-T07. T18-T19 last.

## Parallel examples

T02 ∥ T04; T13 ∥ T06-T08; T12 ∥ T15 once T09 is in.

## Implementation strategy

MVP: Phase 2 + US1 (consent-gated hand values). Then US2 closes the acceptance and the CAM-009 gap, then US3 and polish.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1-R16 and S1-S7 each map to at least one task (R15 → T02, T19; S5 → T19; R16/S7 → T14, T15). No
constitution conflict (Vision and CoreVideo public; consent before analysis; on-device, memory only). Fixed: the
quickstart's DEBUG seed had no task (added to T14); R15's Linux shape had no explicit check (added to T19). No
critical or high findings.
