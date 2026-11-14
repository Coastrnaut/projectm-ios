# Tasks: CAM-005 Camera Focus Point

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/focus-point.md](contracts/focus-point.md)

Tests are requested by the roadmap acceptance ("Tap maps view coordinates to camera focus point
correctly"). Budgets (owner rule 7): unit tests about 1-2 s, the UI test under 30 s. Simulator
results are never device evidence.

## Phase 1: Setup

- [X] CAM-005-T01 Create the feature's simulator "CAM5 iPhone 17" (iOS 27.2) and run `xcodegen generate` in the worktree (no file changes) — Verified 2026-11-14: `xcrun simctl create` (28EAE90D) and `xcodegen generate`

## Phase 2: Foundational (blocks every story)

- [X] CAM-005-T02 Add a Double output-size initializer to `CameraPictureGeometry` in `Packages/Compositor/Sources/CameraLayer/CameraPictureGeometry.swift`; the Int initializer calls it (no behaviour change; existing geometry tests still pass) — Verified 2026-11-14: `swift test --filter Camera` in Packages/Compositor: 68 tests pass (CameraGeometryTests and CameraCropTests unchanged)
- [X] CAM-005-T03 Add the pure mapping `CameraFocusMapping.devicePoint(...)`, `CameraFocusPoint` (0…1, clamped, non-finite → 0.5, `centre`) and `CameraDrawnPicture` in `Packages/Compositor/Sources/CameraLayer/CameraFocusMapping.swift` (contract C1; platform-free) — Verified 2026-11-14: CameraFocusTests mapping tests (hand rows + 4,608-check sweep) pass
- [X] CAM-005-T04 Add the focus seam in `Packages/Compositor/Sources/CameraLayer/CameraFocus.swift`: `CameraFocusMode`, `CameraFocusState`, protocol `CameraFocusConfiguring`, `CameraFocusControl.focus/reset/state` (contract C2) and `FakeCameraFocusDevice` (point support, modes, `refusesConfiguration`, configuration counts, changes outside a configuration); platform-free — Verified 2026-11-14: CameraFocusTests routine tests pass; Linux shape (`-DCOMPOSITOR_NO_METAL`): 6 tests pass
- [X] CAM-005-T05 Conform `AVCaptureDevice` to `CameraFocusConfiguring` in `Packages/Compositor/Sources/CameraLayer/AVCameraLensInventory.swift` (iOS; point before mode) — Verified 2026-11-14: simulator build of projectM-iOS (iOS SDK 27.2) compiles the iOS-only conformance, TEST BUILD SUCCEEDED; real camera behaviour is T14
- [X] CAM-005-T06 Extend `CameraFrameProvider` with `focus`, `onFocusChange`, `setFocusPoint(_:)` and defaults in `Packages/Compositor/Sources/CameraLayer/CameraFrameProvider.swift` (contract C3); `CameraLayerSource.drawnPicture` records the last drawn picture's layout (nil when not drawing) in `Packages/Compositor/Sources/CameraLayer/CameraLayerSource.swift` — Verified 2026-11-14: package build; `swift test --filter Camera` 68 pass

## Phase 3: User Story 1 - Focus where I touch (P1)

**Goal**: a double-tap focuses the running camera at the mapped point; bars ignored.
**Independent test**: mapping table + stand-in provider: a tap sets the expected point and `autoFocus`.

- [X] CAM-005-T07 [US1] Stand-in: `FakeCameraInput` carries its camera's `FakeCameraFocusDevice` (one per camera, `focusPointCameras` on `FakeCameraCaptureSession`) in `Packages/Compositor/Sources/CameraLayer/CameraInputSwitch.swift`; `StubCameraFrameProvider` implements `focus`/`setFocusPoint` and resets on switches and stops in `Packages/Compositor/Sources/CameraLayer/StubCameraFrameProvider.swift` — Verified 2026-11-14: CameraFocusTests stand-in provider tests (3) pass
- [X] CAM-005-T08 [US1] Real camera: `AVCameraFrameProvider` sets the point on its session queue, resets before lens/position switches and on stop/failure, and posts the read-back state in `Packages/Compositor/Sources/CameraLayer/AVCameraFrameProvider.swift` — Verified 2026-11-14: simulator build compiles AVCameraFrameProvider; behaviour on a real camera is T14
- [X] CAM-005-T09 [US1] Package tests in `Packages/Compositor/Tests/CompositorTests/CameraFocusTests.swift`: table-driven mapping across rotations (0/90/180/270) × Fill/Fit × mirror × zoom (1, 2, 3) × anchors (centre, top, bottom), including rect corners, an offset rect and Fit's bars (nil), each row checked against an independent expected value within 0.001 (S1); seam (focus sets point then autoFocus; continuous fallback; unsupported: 0 configurations; refused: unchanged); stand-in provider (tap sets expected point and mode, reported once; no change while idle; lens switch and stop reset to continuous centre; start/stop counts unchanged (R9); state shown is the device's read-back (R12)) — Verified 2026-11-14: `swift test --filter CameraFocusTests`: 9 tests, 0.06 s
- [X] CAM-005-T10 [US1] App: `CameraVisualHost.focus(atWindowPoint:)` (maps against the view's window frame and `drawnPicture`, crop and mirror; no drawn picture yet or not running → nothing) and `-uitestCameraFocusPoint <list|none>` in `Apps/projectM-iOS/Visuals/CameraVisualHost.swift`; observed `cameraFocus` in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`; `Apps/projectM-iOS/Views/CameraFocusRing.swift` with the double-tap modifier (only while the Camera visual is shown), the ring (1 s, Reduce Motion: no animation) and the DEBUG probe `cameraFocusProbe`; wired in `Apps/projectM-iOS/Views/VisualizerView.swift` — Verified 2026-11-14: CameraFocusAppTests.testHostFocusesAtTheMappedPoint and CameraFocusUITests.testDoubleTapFocusesAtTheMappedPoint pass on "CAM5 iPhone 17" (iOS 27.2)

## Phase 4: User Story 2 - Unsupported camera explains its limit (P1)

- [X] CAM-005-T11 [US2] Unsupported tap: no provider call, caption + `.camera` announcement "This camera can't focus on a point."; Settings › Camera focus note (`cameraFocusNote`) in `Apps/projectM-iOS/Views/CameraFocusRing.swift` and `Apps/projectM-iOS/Views/SettingsView.swift` — Verified 2026-11-14: CameraFocusUITests.testUnsupportedCameraExplainsTheLimit and CameraFocusAppTests.testUnsupportedCameraIsNeverConfigured pass

## Phase 5: User Story 3 - Focus without seeing the screen (P2)

- [ ] CAM-005-T12 [US3] VoiceOver action "Focus at centre" on the visualization (only while the camera can focus) and announcement "Focusing at centre" in `Apps/projectM-iOS/Views/CameraFocusRing.swift` — Code done 2026-11-14 (builds; the action is offered only while `cameraFocus.isAdjustable`; `focusAtCentre` uses the tested mapping). Not verified: no test drives the VoiceOver action (the host has no drawn picture without a running frame loop in unit tests); check with VoiceOver on D1 in T14

## Phase 6: User Story 4 - A focus point never outlives its camera (P2)

Covered by T07/T08 (provider resets) and T09/T13 (tests).

## Phase 7: Tests and polish

- [X] CAM-005-T13 App tests `Apps/projectM-iOS/Tests/CameraFocusAppTests.swift` (host maps a window point to the expected camera point with the stand-in, bars ignored, unsupported → 0 configurations, lens switch resets, no stored key) and UI tests `Apps/projectM-iOS/UITests/CameraFocusUITests.swift` (double-tap sets the probed point; unsupported shows the explanation; single tap still shows the controls) — Verified 2026-11-14: CameraFocusAppTests 4 passed (0.14 s), CameraFocusUITests 2 passed (24 s, 25 s); CameraExposureUITests and CameraCropUITests still pass
- [ ] CAM-005-T14 {device} On D1: double-tap near and far objects on the back wide lens and the front camera (mirror on) and with Fit bars; focus follows the finger, bars do nothing; with VoiceOver, the "Focus at centre" action focuses and announces (T12)
- [X] CAM-005-T15 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget, PosterBoard counts; delete the simulator and derived data — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 174 OK; check_privacy_manifest and check_network_symbols OK on the Debug app; no type-check warning in CAM-005 files

## Dependencies

T01 → T02 → T03; T04 → T05, T06 → T07, T08 → T09 → T10 → T11, T12 → T13 → T15. T14 needs a device.

## Parallel opportunities

T03 and T04 (different files); T05 with T07; T11 and T12 (same file: sequential in practice).

## Implementation strategy

MVP = US1 (T01-T10). Then US2, US3, tests and checks.
