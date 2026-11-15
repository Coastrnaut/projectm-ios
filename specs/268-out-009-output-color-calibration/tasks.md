# Tasks: OUT-009 Output Color Calibration

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/display-calibration.md](contracts/display-calibration.md), [quickstart.md](quickstart.md)

Tests are requested by the row's acceptance and the brief. Budgets (owner rule 7): unit ≤ 10 s, UI < 30 s.

## Phase 1: Foundational

- [X] OUT-009-T01 [P] `DisplayCalibration` (ranges, clamping, identity, `exponent`, `apply(encoded:)`, stored codec) and `DisplayCalibrationReceiver` (C1; OUT-009-R1, R2, R9) in Packages/Compositor/Sources/Compositor/DisplayCalibration.swift — Verified 2026-11-14: Compositor `swift test --filter DisplayCalibrationTests` (4 pass, 0.001 s)
- [X] OUT-009-T02 [P] Pure tests: identity at the defaults, gain and gamma maths at representative values, clamping of values and output, codec round trip and malformed input (OUT-009-S1, S2) in Packages/Compositor/Tests/CompositorTests/DisplayCalibrationTests.swift — Verified 2026-11-14: same run, 4 pass

## Phase 2: User Story 1 - Match a projector's colour (P1)

**Independent test**: the external output's pixels follow the transfer function; the device's do not.

- [X] OUT-009-T03 [US1] `cmp_output_calibrated` and `CalibrationBlock`; `Compositor.displayCalibration`, calibrated screen pass only when not the identity, `calibratedFrames` (C2; OUT-009-R2, R3, R5) in Packages/Compositor/Sources/Compositor/CompositorShaders.swift and Compositor.swift — Verified 2026-11-14: DisplayCalibrationOutputTests (T04) and the whole CompositorTests target on the host (645 tests, 0 failures, 22.7 s)
- [X] OUT-009-T04 [US1] GPU tests: a reference ramp through the calibrated pass matches the Swift reference within one 8-bit step; the identity uses the plain pass (bit-identical); `encodeOutput` stays uncalibrated (OUT-009-S1, S2, S4) in Packages/Compositor/Tests/CompositorTests/DisplayCalibrationOutputTests.swift — Verified 2026-11-14: `swift test --filter DisplayCalibration` (2 GPU tests pass, 0.34 s, on the Mac's Metal device)
- [X] OUT-009-T05 [US1] CFlashLimiter calibration uniforms and `PMFlashLimiterDrawOutput`; ANGLERenderer applies its view's calibration and keeps captures uncalibrated (C3; OUT-009-R2, R3, R5) in Packages/Rendering/Sources/CFlashLimiter/ and Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift — Verified 2026-11-14: DisplayCalibrationGLTests (T06) plus FlashLimiterTests (7) and ANGLECaptureTests (2) unchanged, iOS 27.2 simulator "OUT9 iPhone 17"
- [X] OUT-009-T06 [US1] GL tests: a solid frame through the limiter with a calibration matches the prediction; identity unchanged; a capture during calibration is uncalibrated while the shown frame is calibrated in Packages/ANGLERendering/Tests/ANGLERenderingTests/DisplayCalibrationGLTests.swift — Verified 2026-11-14: 2 pass (0.06 s, 0.08 s) on the iOS 27.2 simulator; 11 tests in the run, 0 failures
- [X] OUT-009-T07 [US1] Receivers: `NativeSpectrumLayerView` (accepts only with a handler) and the four compositor hosts install the handler (C3; OUT-009-R3) in Apps/projectM-iOS/Visuals/ — Verified 2026-11-14: DisplayCalibrationAppTests (the Photo host's compositor takes the calibration inside the call; a bare NativeSpectrumLayerView reports unsupported), iOS 27.2 simulator "OUT9 iPhone 17"
- [X] OUT-009-T08 [US1] Routing: `VisualSlotView.calibration`, `ExternalDisplayCoordinator.displayCalibration` and `calibrationSummary`, live during a recording hold (C4; OUT-009-R4, R6, R7) in Apps/projectM-iOS/ExternalDisplay/ — Verified 2026-11-14: DisplayCalibrationAppTests (external slot applies, device slot identity, hold not deferring, blackout black, summary); CornerPinAppTests, ExternalOutputModeAppTests, ExternalOutputCorrectionTests pass unchanged

## Phase 3: User Story 2 - Calibration never edits the show (P1)

- [X] OUT-009-T09 [US2] App acceptance test: a Photo host on the external stand-in renders predicted calibrated pixels while its recording output stays uncalibrated; on the device slot it is uncalibrated; a native spectrum view reports unsupported; the scene document bytes, scene inputs and autosave revision are identical before and after; the blackout still reads black (OUT-009-R4 to R7, S2 to S4) in Apps/projectM-iOS/Tests/DisplayCalibrationAppTests.swift — Verified 2026-11-14: testCalibrationChangesTheExternalOutputButNotTheSceneTheRecordingOrTheDevice passes (0.18 s): every pixel within 2/255 of the prediction, recording output = uncalibrated frame, scene document bytes and inputs identical, autosave revision unchanged

## Phase 4: User Story 3 - Adjust accessibly, reset, keep (P2)

- [X] OUT-009-T10 [US3] `ExternalOutputSetting.calibration` and its key; key lists (`ExternalOutputSetting.keys`, FILE-005 excluded keys, `LibraryErasePolicy.externalDisplayKeys`, `ALLOWED_KEYS`, LibraryBackupAppTests) (C4; OUT-009-R9) in Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift and the listed files — Verified 2026-11-14: LibraryBackupAppTests and SettingsTests pass (simulator), LibraryBackup `swift test` 87 pass, `test_scripts.py` 179 OK
- [X] OUT-009-T11 [US3] Editor (sliders via `.accessibleParameter`, readouts, Reset, uncovered-visuals note) and the Settings row (C5; OUT-009-R8) in Apps/projectM-iOS/Views/DisplayCalibrationEditorView.swift and ExternalDisplaySection.swift — Verified 2026-11-14: DisplayCalibrationUITests (T13) drives it; no type-check warnings above the budget in the new or touched files
- [X] OUT-009-T12 [US3] Persistence test (stored, applied at launch, identity removes, malformed reads identity, clamped) in Apps/projectM-iOS/Tests/DisplayCalibrationAppTests.swift; DEBUG probe `externalCalibration` (C6; OUT-009-R10) in Apps/projectM-iOS/Debug/UITestExternalDisplay.swift — Verified 2026-11-14: testTheCalibrationPersistsAndReadsSafely passes; the probe is read by T13
- [X] OUT-009-T13 [US3] UI test: open the editor with the fake display, raise gamma, the probe reports custom/applied, Reset returns to identity (< 30 s) in Apps/projectM-iOS/UITests/DisplayCalibrationUITests.swift — Verified 2026-11-14: passes 3 of 3 runs on the iOS 27.2 simulator (20.8 s, 19.6 s, 31.2 s; the last on a busy shared Mac)

## Phase 5: Device

- [ ] OUT-009-T14 {device} Quickstart step 4 on D1 with a real display or projector (OUT-009-S2, S4 on hardware)

## Dependencies

T01 → T02, T03, T05, T07; T03 → T04; T05 → T06; T07, T08 → T09; T08 → T10 → T11, T12 → T13.

## Analysis (speckit-analyze, 2026-11-14)

Every requirement maps to a task (R1 T01/T10; R2 T01-T06; R3 T03/T05/T07; R4 T08/T09; R5 T03-T06/T09; R6-R7 T08/T09;
R8 T11/T13; R9 T10/T12; R10 T12/T13) and every success criterion to a test (S1 T02/T04/T06; S2 T04/T06/T09; S3 T09;
S4 T04/T09; S5 T12). No conflicts between spec, plan and contract; the uncovered visuals are named in the spec,
research D2, the editor footer and the report.
