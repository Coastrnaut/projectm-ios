# Tasks: CAM-002 Front Camera Layer

**Input**: `specs/096-cam-002-front-camera-layer/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (CAM-002-S1 to S6). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, UI test under 30 s. `{device}` tasks are the final device
stage and stay open until a person runs them on D1-D3.

## Phase 1: Setup

- [ ] CAM-002-T01 Run `xcodegen generate`, create the simulator "CAM2 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run (owner rule 5)

## Phase 2: Foundational (blocks every story)

- [ ] CAM-002-T02 [P] `CameraPosition` (`back` default, `front`; raw values `"back"`/`"front"`; `title`; `defaultMirrored`: front true, back false) and `CameraFeedState.notice(position:)` / `accessibilityValue(position:)` (front unavailable: "No front camera is available. Showing the spectrum only." / "No front camera") in `Packages/Compositor/Sources/CameraLayer/CameraFeedState.swift`
- [ ] CAM-002-T03 [P] `CameraPictureGeometry.mirrored` (flip the upright x, a ← 1 − a, before the rotation mapping; typed steps) in `Packages/Compositor/Sources/CameraLayer/CameraPictureGeometry.swift`
- [ ] CAM-002-T04 CPU tests in `Packages/Compositor/Tests/CompositorTests/CameraGeometryTests.swift`: mirror matrix (front/back × mirror on/off × the four turns), expected texture coordinate at the four corners and the center; positions, defaults and front notices (CAM-002-S1)
- [ ] CAM-002-T05 `CameraFrame.position`, `LatestCameraFrame.store(_:owner:position:)` and `setPosition`, protocol `position` / `select(_:)` with default implementations in `Packages/Compositor/Sources/CameraLayer/CameraFrameProvider.swift`
- [ ] CAM-002-T06 `CameraLayerSource.mirrored` (uniform `mirror` replaces `pad`, 32 bytes) and the position filter (draw only `frame.position == provider.position`) in `Packages/Compositor/Sources/CameraLayer/CameraLayerSource.swift`
- [ ] CAM-002-T07 `StubCameraFrameProvider`: `position`, `availablePositions`, `select(_:)` per data-model.md (clear the slot, restart into the new position, `selectCount`), pattern `.marker(background:marker:)` (top-left quarter) in `Packages/Compositor/Sources/CameraLayer/StubCameraFrameProvider.swift`
- [ ] CAM-002-T08 GPU tests in `Packages/Compositor/Tests/CompositorTests/CameraLayerTests.swift`: the marker is top-left unmirrored and top-right mirrored; toggling `mirrored` flips the next frame without a restart; a switch to front shows the front picture, never a stale back picture; missing front → `unavailable`, transparent fallback; Front chosen before the first (simulated) prompt shows the front picture after Allow (the stand-in answers synchronously; the AV path keeps the last choice by design, device stage)

## Phase 3: User Story 1 - The front camera behind the music (P1) — MVP

**Independent test**: Camera › Front with the stand-in camera shows its picture, the badge reads "Front camera on", frames grow.

- [ ] CAM-002-T09 [US1] `AVCameraFrameProvider`: `camera(for:)` (wide-angle per position), `position`, `select(_:)` (live input swap inside begin/commit configuration on the session queue, slot closed until the video queue drains, new `RotationCoordinator`; stop/start from unavailable, interrupted or failed), stamp pictures from the connection's `sourceDevicePosition` in `Packages/Compositor/Sources/CameraLayer/AVCameraFrameProvider.swift`
- [ ] CAM-002-T10 [US1] `AppSettings`: `cameraPosition` (`settings.camera.position`, unknown → back), `cameraMirrorFront` (`settings.camera.mirrorFront`, absent → true), `cameraMirrorBack` (`settings.camera.mirrorBack`, absent → false), `cameraMirrored`; keys in `allKeys` in `Apps/projectM-iOS/Coordinators/AppSettings.swift`; keys in `ALLOWED_KEYS` of `scripts/run_device_tests.py`
- [ ] CAM-002-T11 [US1] `CameraVisualHost.cameraPosition` and `mirrored` (forward to provider and layer; `make(…, position:, mirrored:)`), coordinator applies settings on creation and in `cameraSettingsChanged()` in `Apps/projectM-iOS/Visuals/CameraVisualHost.swift`, `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`, `Apps/projectM-iOS/Views/VisualizerView.swift`
- [ ] CAM-002-T12 [US1] Settings "Camera" section (segmented `cameraPositionPicker` "Camera" Back/Front, `cameraMirrorToggle` "Mirror"), footer text, Visual footer mentions front or rear in `Apps/projectM-iOS/Views/SettingsView.swift`
- [ ] CAM-002-T13 [US1] Badge "Front camera on" (`CameraIndicator(state:position:)`) in `Apps/projectM-iOS/Views/CameraIndicator.swift`; `PermissionCatalog.cameraNotice(for:position:)` in `Apps/projectM-iOS/Coordinators/PermissionCatalog.swift`
- [ ] CAM-002-T14 [US1] Usage description (spec Clarifications) in `project.yml`, `PermissionCatalog.swift` and `docs/privacy-policy.md` together; `python3 scripts/check_permission_catalog.py` passes
- [ ] CAM-002-T15 [US1] App unit tests `Apps/projectM-iOS/Tests/FrontCameraTests.swift`: settings defaults, per-position mirror, persistence through a new `AppSettings`, reset keys, not in scenes; badge label; the status-bar rule does not depend on position (R8); host forwards position and mirror without restarting the loop or re-asking

## Phase 4: User Story 2 - Mirror and saved output match the screen (P1)

**Independent test**: marker picture; for mirror on and off the marker is on the same side in the composite, a REC-001 capture and the REC-003 output pass.

- [ ] CAM-002-T16 [US2] Acceptance test in `Apps/projectM-iOS/Tests/FrontCameraTests.swift`: one frame of the Camera visual host composited offscreen with the composite's REC-001 capture requested and the REC-003 output pass encoded in the same command buffer; read pixels from all three; marker side equal for mirror on and off, front and back (CAM-002-S2, S3). OUT-001 shows the same host view and compositor (research CAM-002-D2), so the composite stands for the external display

## Phase 5: User Story 3 - Switching cameras safely (P1)

**Independent test**: stand-in switching shows only the chosen camera's pictures, source started once; missing front shows the front notice; denied reuses FILE-013's notice.

- [ ] CAM-002-T17 [US3] Host tests in `Apps/projectM-iOS/Tests/FrontCameraTests.swift`: switching while running, no stale frame, loop and analysis untouched; missing front notice via `PermissionCatalog.cameraNotice`; denied/restricted notices identical for both positions (CAM-002-S4, R10)
- [ ] CAM-002-T18 [US3] UI test `Apps/projectM-iOS/UITests/FrontCameraUITests.swift` (`-uitestCamera granted`): choose Camera, pick Front, see "Front camera on"; toggle Mirror and see its value; source started once; under 30 s (CAM-002-S5)

## Phase 6: Polish & Cross-Cutting

- [ ] CAM-002-T19 Amend ADR-0017 (front camera, mirror point, settings, usage text) in `docs/adr/0017-rear-camera-layer.md`; spec status
- [ ] CAM-002-T20 Run `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`, `check_privacy_manifest.py <Debug .app>`; the package tests; the app tests (projectM-iOSTests, CameraUITests, CameraPrivacyStatusUITests, PermissionAuditUITests, FrontCameraUITests, the frame-capture and recording UI tests); PosterBoard count after; delete the simulator
- [ ] CAM-002-T21 {device} D1-D3: quickstart device stage steps 1-2 (front camera upright and mirrored in portrait and landscape, badge, iOS indicator)
- [ ] CAM-002-T22 {device} D1: quickstart step 3 (Mirror flips at once; Save Frame and Record match the screen for mirror on and off)
- [ ] CAM-002-T23 {device} D1-D3: quickstart step 4 (switching within 2 s, no frame of the old camera, audio uninterrupted; CAM-002-S7)

## Dependencies

T01 → T02-T08 (T02, T03 parallel; T05 before T06, T07) → US1 (T09-T15) → US2 (T16) and US3
(T17, T18) → T19, T20 → device stage T21-T23.

## Parallel examples

- T02 and T03 (different files); T12 and T13 after T10.
- T16 and T17 share a file: one writer, sequential.

## Implementation strategy

MVP is US1 (front camera with mirror on screen); US2 proves the acceptance; US3 hardens switching.

## Analysis (speckit-analyze, 2026-11-14)

100 % of R1-R12 and S1-S7 have tasks; no critical finding. Applied: C1 (OUT-001 noted in T16), C2 (prompt-time switch in T08), C3 (status-bar rule in T15).
