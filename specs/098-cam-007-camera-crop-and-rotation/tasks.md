# Tasks: CAM-007 Camera Crop and Rotation

**Input**: `specs/098-cam-007-camera-crop-and-rotation/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (CAM-007-S1 to S5). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, UI test under 30 s. `{device}` tasks are the final device
stage and stay open until a person runs them on D1-D3.

## Phase 1: Setup

- [ ] CAM-007-T01 Run `xcodegen generate`, initialize the preset submodules if missing, create the simulator "CAM7 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run (owner rule 5)

## Phase 2: Foundational (blocks every story)

- [ ] CAM-007-T02 [P] `CameraCropMode` (`fill` default, `fit`; raw values `"fill"`/`"fit"`; titles Fill/Fit), `CameraCropAnchor` (`centre` default, `top`, `bottom`; raw values `"centre"`/`"top"`/`"bottom"`; `y` 0.5/0/1; titles Centre/Top/Bottom), `CameraCrop` (`mode`, `anchor`, `zoom`; `zoomChoices` [1, 1.5, 2, 3], any other or non-finite zoom → 1; `.fill`; `zoomTitle` "1×"…, `zoomSpokenValue` "1 times"…) in `Packages/Compositor/Sources/CameraLayer/CameraCrop.swift`
- [ ] CAM-007-T03 `CameraPictureGeometry.init(…, mirrored:, crop: = .fill)` per contracts/camera-crop.md (base scale max for Fill, min for Fit, times zoom; offset = (1 − visible) × anchor; typed steps) and `contains(x:y:)` (tolerance 1e-4) in `Packages/Compositor/Sources/CameraLayer/CameraPictureGeometry.swift`
- [ ] CAM-007-T04 CPU geometry table in `Packages/Compositor/Tests/CompositorTests/CameraCropTests.swift`: pictures 1920×1080 and 1080×1920 × the four turns × mirror on/off × outputs portrait phone (1179×2556), landscape phone (2556×1179), iPad 4:3 (1640×2360 and 2360×1640) × modes × anchors × zooms: no stretch (aspect error < 0.1 %), Fill covered, Fit at 1× whole picture, anchor point at its output point, zoom ratio kept across portrait→landscape; `.fill` equals the old geometry; crop value snapping and titles (CAM-007-S1, S3); also run in the Linux shape

## Phase 3: User Story 1 - The framing survives turning the device (P1) — MVP

**Independent test**: marker picture at a portrait and then a landscape layer size: center lines at the predicted relative positions per mode, Fill covered, Fit bars transparent.

- [ ] CAM-007-T05 [US1] `CameraLayerSource.crop` (main thread, read per frame, never restarts) and the shader's transparent output outside the picture (same tolerance) in `Packages/Compositor/Sources/CameraLayer/CameraLayerSource.swift`
- [ ] CAM-007-T06 [US1] GPU pixel tests in `Packages/Compositor/Tests/CompositorTests/CameraLayerTests.swift`: stand-in `.marker` picture (red top-left quarter) with a quarter turn, composited at portrait (48×64) then landscape (64×48) sizes for Fill Centre 1×, Fill Top 2× and Fit Centre 1×: the marker's right and bottom edges (the picture's center lines) at the positions the geometry predicts (≤ 2 px), the anchor point's output position the same relative point in both sizes, Fill alpha 1 everywhere, Fit bars alpha 0; crop changes never restart the camera (CAM-007-S2, S5)

## Phase 4: User Story 2 - Choosing Fill or Fit, an anchor and a zoom (P1)

**Independent test**: Settings › Camera with the stand-in camera: Fit, Top and 2 times show in the controls; persistence through a new `AppSettings`.

- [ ] CAM-007-T07 [US2] `AppSettings`: `cameraCropMode` (`settings.camera.cropMode`, unknown → fill), `cameraCropAnchor` (`settings.camera.cropAnchor`, unknown → centre), `cameraZoom` (`settings.camera.zoom`, not in {1, 1.5, 2, 3} → 1), `cameraCrop`; keys in `allKeys` in `Apps/projectM-iOS/Coordinators/AppSettings.swift`; keys in `ALLOWED_KEYS` of `scripts/run_device_tests.py`
- [ ] CAM-007-T08 [US2] `CameraVisualHost.crop` and `make(…, crop:)`; the coordinator passes `settings.cameraCrop` on creation and in `cameraSettingsChanged()`; `VisualizerView` observes the three settings, in `Apps/projectM-iOS/Visuals/CameraVisualHost.swift`, `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`, `Apps/projectM-iOS/Views/VisualizerView.swift`
- [ ] CAM-007-T09 [US2] Settings Camera section: segmented "Crop" (`cameraCropModePicker`), "Anchor" (`cameraCropAnchorPicker`), "Zoom" (`cameraZoomPicker`) with labels and spoken values, footer text, in `Apps/projectM-iOS/Views/SettingsView.swift`
- [ ] CAM-007-T10 [US2] App unit tests `Apps/projectM-iOS/Tests/CameraCropTests.swift`: defaults, persistence through a new `AppSettings` (relaunch), unknown values → defaults, keys in `allKeys`, shared by both cameras, never chooses the Camera visual, not recorded in scenes or cues; host forwards the crop without restarting the camera or the loop (CAM-007-R5, R6, S5)
- [ ] CAM-007-T11 [US2] UI test `Apps/projectM-iOS/UITests/CameraCropUITests.swift` (`-uitestCamera granted`): choose Camera, open Settings, scroll to Camera, pick Fit, Top and 2×; values read back (CAM-007-S4; under 30 s)

## Phase 5: User Story 3 - Saved output matches the screen (P2)

**Independent test**: one composite of the host with a REC-001 capture: the framing in both is identical.

- [ ] CAM-007-T12 [US3] Acceptance test in `Apps/projectM-iOS/Tests/CameraCropTests.swift`: the Camera visual host composited offscreen at a portrait then a landscape size for Fill Top 2× and Fit; the composite's corner pixels and the REC-001 capture agree (Fit: black bars at the predicted sides; Fill: picture everywhere), mirror on and off (CAM-007-R8)

## Phase 6: Polish & cross-cutting

- [ ] CAM-007-T13 ADR-0017 amendment (decisions 9-10: crop model and placement rule, transparent Fit bars; defaults unchanged) in `docs/adr/0017-rear-camera-layer.md`
- [ ] CAM-007-T14 Run `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`, `check_privacy_manifest.py <Debug .app>`; PosterBoard count after; delete the simulator
- [ ] CAM-007-T15 {device} D1: quickstart device steps 1-4 (Back and Front, each mode, portrait ↔ landscape, Save Frame) (CAM-007-S6)
- [ ] CAM-007-T16 {device} D2 and D3: the same steps on the iPads (4:3 screen, iPadOS 26.5 on D3) (CAM-007-S6)

## Dependencies

T01 → T02 → T03 → T04; T03 → T05 → T06; T03 → T07 → T08 → T09 → T10, T11; T08 → T12; T13 any
time after T03; T14 after all code; T15-T16 last (device stage).

## Parallel opportunities

T02 and the spec-side T13 draft; T04 (CPU) and T05 (shader) after T03; T10 and T11 after T09.

## Implementation strategy

MVP = Phases 2-3 (the geometry and the layer, which make the acceptance hold), then the settings
and UI (US2), then the saved-output check (US3), then polish and the device stage.
