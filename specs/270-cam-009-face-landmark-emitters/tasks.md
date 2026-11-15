# Tasks: CAM-009 Face Landmark Emitters

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/face-sources.md](contracts/face-sources.md)

Budgets (owner rule 7): unit tests ≤ 2 s, suites < 1 min, UI test < 30 s.

## Phase 1: Foundation (pure Swift, Linux)

- [X] CAM-009-T01 Add `FaceFeature`, `FaceFeatureValues`, `FacePoint`, `FaceObservationSample`, `FaceFeatureNormalizer`, `FaceFeatureTracker`, `FaceAnalysisSchedule`, `FaceTrackingRate`, `FaceTrackingGate` in `Packages/ParameterGraph/Sources/ParameterGraph/FaceFeatureTracker.swift` (R6, R7, R9, R10, R15) — Verified 2026-11-14: swift test --package-path Packages/ParameterGraph (298 passed, 0 failed)
- [X] CAM-009-T02 Add `.face(FaceFeature)` to `AudioFeatureSource` (ID, parse, value from `AudioFeatureFrame.face`); refuse in `ExpressionCatalog`, unreachable constant in `ExpressionCompiler` (R8) — Verified 2026-11-14: FaceFeatureTrackerTests.testSourceIDsRoundTrip…, ExpressionRejectionTests.testFaceSourcesAreNotFormulaNames
- [X] CAM-009-T03 [P] `FaceFeatureTrackerTests`: normalisation (centred neutral, mouth full, eyes, mirrored x, roll/yaw), bounds for extreme/degenerate/non-finite samples, smoothing and absence, schedule, gate truth table, source IDs and expression refusal (S2) — Verified 2026-11-14: FaceFeatureTrackerTests, 7 tests pass on the host in < 1 ms each

## Phase 2: Frame path and analyzer (US1)

- [X] CAM-009-T04 `CameraPictureAnalyzing` and `pictureAnalyzer` hook in `CameraFrameProvider.swift`; offer in `AVCameraFrameProvider` and `StubCameraFrameProvider`; `CameraLayerSource.stop()` resets it (R4) — Verified 2026-11-14: CompositorTests.CameraPictureAnalyzerTests passes; Compositor builds with -DCOMPOSITOR_NO_METAL (Linux shape)
- [X] CAM-009-T05 `Apps/projectM-iOS/Coordinators/FaceLandmarkAnalyzer.swift`: `FaceLandmarkDetecting`, `VisionFaceLandmarkDetector` (lazy request, largest face, copy scalars), `StubFaceLandmarkDetector` (DEBUG/tests), `FaceLandmarkAnalyzer` (gate flag, schedule, lazy factory, generation, injected runner and clock) (R1, R2, R10, R11) — Verified 2026-11-14: FaceTrackingAppTests (gate, throttle, unavailable detector) on the CAM9 iOS 27.2 simulator
- [X] CAM-009-T06 `Apps/projectM-iOS/Coordinators/FaceTrackingCoordinator.swift`: switch and consent keys, sheet state, permission, gate → analyzer, status, announcement, connect to camera and native hosts (R1-R5, R13) — Verified 2026-11-14: FaceTrackingAppTests.testConsentGatePrecedesAnyFaceAnalysis
- [X] CAM-009-T07 Wire it: `AppCoordinator` (lazy coordinator, camera host and native host connect, scene activity), `NativeSpectrumHost` (`usesFace`, `faceValues`), `ParameterInspectorModel` names (R8) — Verified 2026-11-14: FaceTrackingAppTests.testMouthOpenBindingDrivesTheGlow; app builds

## Phase 3: UI and indicator (US1, US3)

- [X] CAM-009-T08 `CameraFaceTrackingRow` (switch, note, consent sheet) in `SettingsView.cameraSection`; `VisualizerView` passes it; camera badge shows "Face tracking" while analysing (R2, R5, R13) — Verified 2026-11-14: FaceTrackingConsentUITests (25 s); CameraPersonMaskUITests still pass
- [X] CAM-009-T09 Keys: `run_device_tests.py` ALLOWED_KEYS, `LibrarySettingsPolicy.excludedKeys`, UI-test reset, `LibraryBackupAppTests` appKeys (R3) — Verified 2026-11-14: LibraryBackupAppTests, SettingsTests, LibraryBackup package (87 tests, incl. erase classification)
- [X] CAM-009-T10 The performance overlay shows only "Face tracking on/off"; the performance report gains nothing (R13) — Verified 2026-11-14: app builds; FaceTrackingAppTests asserts the performance report holds no face data (the overlay line itself is not UI-tested; the report schema is unchanged, spec R13)

## Phase 4: Proof

- [X] CAM-009-T11 `FaceTrackingAppTests`: consent gate with a spy factory (S1), permission denied message, switch off flat, binding drives the glow (US2), container snapshot unchanged and no face keys in scene capture or performance report (S3), source scan for logging/file/network calls (R11, R12) — Verified 2026-11-14: FaceTrackingAppTests, 5 tests pass
- [X] CAM-009-T12 `FaceTrackingConsentUITests`: the sheet appears before activation; Cancel leaves the switch off (S5) — Verified 2026-11-14: FaceTrackingConsentUITests passes (25.4 s)
- [X] CAM-009-T13 ADR-0081, privacy policy paragraph (R14) — Verified 2026-11-14: validate_docs OK
- [X] CAM-009-T14 Repo checks: compliance, docs, motion policy, permission catalog, status events, script tests; privacy manifest and network symbols on the built app (S4) — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 179 OK; check_privacy_manifest and check_network_symbols OK on the Debug simulator app
- [X] CAM-009-T15 Type-check budget pass on touched files; `LibraryBackupAppTests`, `SettingsTests` pass — Verified 2026-11-14: build with -warn-long-* flags: no warning in a touched function or expression (three pre-existing ones under load 113: AppCoordinator.init, SettingsView:296, VisualizerView:68); LibraryBackupAppTests and SettingsTests pass

## Phase 5: Device

- [ ] CAM-009-T16 {device} On D1: a real face drives the sources, the badge and iOS's indicator show, the frame rate with tracking on stays within 5 % (quickstart)

## Dependencies

T01 → T02 → T03; T01 → T05 → T06 → T07 → T08; T04 → T05; T06 → T09, T10; T07-T10 → T11, T12; all → T14, T15.

## Analyze (2026-11-14)

Coverage check of spec ↔ plan ↔ tasks: every requirement R1-R15 maps to a task (R14 → T13, R15 → T03/T04). Fix
applied: R13 narrowed to the overlay (the PERF-012 report has a fixed schema and gains nothing; T10 and the
Clarifications now say so). No other inconsistency found.
