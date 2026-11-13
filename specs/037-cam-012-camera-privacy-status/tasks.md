# Tasks: CAM-012 Camera Privacy Status

**Input**: `specs/037-cam-012-camera-privacy-status/` (spec, plan, research, data-model, contracts,
quickstart). Tests are requested by the spec (CAM-012-R10, S1-S4). Budgets (owner rule 7): unit
tests about 1-2 s (≤ 10 s), UI test under 30 s; no wall-clock assertions. `{device}` tasks are the
final device stage, left to the owner.

Format: `- [ ] CAM-012-Tnn [P?] [Story?] Description`.

## Phase 1: Setup

- [ ] CAM-012-T01 Create the simulator `CAM12 iPhone 17` (iOS 27.2), run `xcodegen generate` in the worktree, count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`

## Phase 2: Foundational

- [ ] CAM-012-T02 `CameraIndicator` value type: `isShown` = `.starting || .running`, `accessibilityValue` "Starting"/"Live", constants "Camera on", "Stop camera", "Camera off" (contract) in `Apps/projectM-iOS/Views/CameraIndicator.swift`
- [ ] CAM-012-T03 [P] `AppSettings.visualBeforeCamera`: the stored `settings.visual` key, projectM when absent, unknown or `camera` (data-model "Fallback visual"; read only) in `Apps/projectM-iOS/Coordinators/AppSettings.swift`

## Phase 3: User Story 1 - See at a glance that the camera is on (P1)

**Goal**: the badge is shown exactly while the feed is starting or running (R1, R2, R9).
**Independent test**: with the stub, the indicator follows start, pause, background, interruption, denial.

- [ ] CAM-012-T04 [US1] `AppCoordinator.cameraIndicator` (`CameraIndicator(state: cameraState)`, shown only while `showsCameraVisual`) in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`
- [ ] CAM-012-T05 [US1] Badge view (camera symbol, "Camera on", Stop camera button; identifiers `cameraIndicator`, `stopCamera`; label and value per contract) shown at the top of `Apps/projectM-iOS/Views/VisualizerView.swift` whenever `cameraIndicator.isShown`, independent of the controls
- [ ] CAM-012-T06 [P] [US1] Unit tests: indicator rule for every `CameraFeedState`; with the stub host, the indicator follows start, pause, background/foreground, interruption and its end, and denial (S1) in `Apps/projectM-iOS/Tests/CameraPrivacyStatusTests.swift`

## Phase 4: User Story 2 - Stop the camera with one tap (P1)

**Goal**: Stop camera stops the feed once, drops the picture, returns to the fallback visual and keeps rendering (R3-R8).
**Independent test**: with the stub, Stop calls the provider's stop exactly once, the loop keeps compositing, and the UI shows the fallback with the source started once.

- [ ] CAM-012-T07 [US2] `CameraVisualHost.stopCamera()` (synchronous provider stop, `cameraStoppedByUser` blocks any restart in `updateLoop()`), `framesComposited` counter (no allocation) in `Apps/projectM-iOS/Visuals/CameraVisualHost.swift`
- [ ] CAM-012-T08 [US2] `AppCoordinator.stopCamera()`: host `stopCamera()`, announce "Camera off", `settings.visual = settings.visualBeforeCamera`, `visualSettingsChanged()`; never touches the audio source; wired to the badge's button in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`
- [ ] CAM-012-T09 [P] [US2] Unit tests: Stop calls the stub's stop exactly once (`stopCount == 1` also after release), drops the picture, reports idle, and resume/foreground/scene/presentation never restart it; `visualBeforeCamera` returns the stored visual and writes nothing; the frame loop keeps compositing after Stop with no deadlock (expectation, 10 s ceiling) (S2, S4) in `Apps/projectM-iOS/Tests/CameraPrivacyStatusTests.swift`
- [ ] CAM-012-T10 [US2] UI test: `-uitestCamera granted`; choose Circular Spectrum then Camera; badge appears with value "Live"; tap Stop camera; badge and camera visual disappear, circular spectrum shown, `sourceStarts` stays "1", pause/resume works and the camera does not return (S1-S4) in `Apps/projectM-iOS/UITests/CameraPrivacyStatusUITests.swift`

## Phase 5: Polish

- [ ] CAM-012-T11 [P] One sentence on the in-app badge and Stop camera in `docs/privacy-policy.md` ("The camera picture stays on your screen")
- [ ] CAM-012-T12 Gates: `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, app unit tests (`projectM-iOSTests`) and `CameraUITests` + `CameraPrivacyStatusUITests` on the CAM12 simulator; PosterBoard reports counted before/after; delete the CAM12 simulator
- [ ] CAM-012-T13 {device} On D1: choose Camera, tap Stop camera; iOS's camera indicator turns off within one second, the previous visual keeps animating, music continues; pause/resume and lock/unlock do not restart the camera (S5; quickstart "Device")

## Dependencies

T01 → T02, T03 → US1 (T04 → T05; T06 after T04) → US2 (T07 → T08 → T09, T10) → T11, T12 → T13.
US2 needs US1's badge for its button. T03 and T06/T09 (tests in one file, written in order) and T11
can run beside implementation.

## Implementation strategy

MVP is US1 + US2 together (both P1; the row needs both). Build once after T08, run the unit tests,
then the UI tests, then the gates.
