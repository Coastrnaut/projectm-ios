# Tasks: OUT-007 Corner-Pin Warp

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/corner-pin.md](contracts/corner-pin.md), [quickstart.md](quickstart.md)

Tests are requested by the row's acceptance and the brief. Budgets (owner rule 7): unit ≤ 10 s, UI < 30 s.

## Phase 1: Foundational

- [ ] OUT-007-T01 [P] `CornerPinPoint`, `CornerPin` (identity, validity, clamped-or-refused `moving`/`nudging`, stored codec) and `Homography` (Heckbert solve, `map`, `jacobianDeterminant`, `layerMatrix`) (C1; OUT-007-R1, R3, R4) in Packages/PresentationLifecycle/Sources/PresentationLifecycle/CornerPin.swift
- [ ] OUT-007-T02 [P] Package tests: unit corners → quad within 1e-9, interior points inside the quad, identity is identity; concave, bow-tie, collinear, tiny and out-of-range quads rejected; dense-grid positive Jacobian for valid quads; edits refused or clamped; stored codec round trip and malformed input (OUT-007-S1 to S3, S5) in Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/CornerPinTests.swift

## Phase 2: User Story 1 - Square the picture on a tilted projector (P1)

**Independent test**: with the external stand-in, a pin's projected slot corners land on the quad; the card shows while calibrating.

- [ ] OUT-007-T03 [US1] Calibration card layer drawing OUT-012's test card (C2; OUT-007-R5) in Apps/projectM-iOS/ExternalDisplay/CornerPinCardLayer.swift
- [ ] OUT-007-T04 [US1] `cornerPin` → `sublayerTransform` (external role only, no implicit animation, re-applied on layout) and `showsCalibrationCard` (C2; OUT-007-R2, R6, R8) in Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift
- [ ] OUT-007-T05 [US1] `cornerPin`, `isCalibrating`, `calibrationAspect`, `cornerPinSummary`, pushed to existing and new external slots inside the call, never deferred by the hold (C3; OUT-007-R6, R7) in Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift
- [ ] OUT-007-T06 [US1] App tests: projecting the slot's corners through the applied `sublayerTransform` lands on the quad in slot coordinates; the external stand-in shows the transform while the device slot and its visual keep identity; a recording hold does not defer it; the card shows only while calibrating and the blackout cover stays above it (OUT-007-R2, R6 to R8, S1, S4) in Apps/projectM-iOS/Tests/CornerPinAppTests.swift

## Phase 3: User Story 2 - Adjust precisely without dragging (P1)

- [ ] OUT-007-T07 [US2] `CornerPinEditorView`: display shape, warped outline, four draggable handles with accessibility values and Move actions, corner picker, nudge buttons, Reset, Done; opens/closes calibration (C4; OUT-007-R4, R5) in Apps/projectM-iOS/Views/CornerPinEditorView.swift
- [ ] OUT-007-T08 [US2] "Corner pin…" row and full-screen cover (C4) in Apps/projectM-iOS/Views/ExternalDisplaySection.swift

## Phase 4: User Story 3 - The correction is kept (P2)

- [ ] OUT-007-T09 [US3] `cornerPin` stored under `settings.externalDisplay.cornerPin` in `ExternalOutputSetting.keys`, applied to the coordinator at init and on change, strings and footer (C4; OUT-007-R9, S5) in Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift and Apps/projectM-iOS/Coordinators/AppCoordinator+ExternalDisplay.swift; persistence test in Apps/projectM-iOS/Tests/CornerPinAppTests.swift
- [ ] OUT-007-T10 [US3] Key lists: `ALLOWED_KEYS` in scripts/run_device_tests.py, `excludedKeys` in Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, `externalDisplayKeys` in Packages/LibraryBackup/Sources/LibraryBackup/LibraryErasePolicy.swift (LibraryBackupAppTests reads `ExternalOutputSetting.keys`)

## Phase 5: Polish

- [ ] OUT-007-T11 DEBUG probe `externalCornerPin` (C5; OUT-007-R10) in Apps/projectM-iOS/Debug/UITestExternalDisplay.swift and UI test in Apps/projectM-iOS/UITests/CornerPinUITests.swift (< 30 s); run the repo checks, LibraryBackupAppTests, SettingsTests, ExternalDisplayCoordinatorTests, ExternalOutputCorrectionTests
- [ ] OUT-007-T12 {device} D1 with a real projector: quickstart B (corners match the screen, straight lines straight, phone and recording unwarped, relaunch keeps it)

## Dependencies

T01 → T02, T04 → T05 → T06; T03 → T04; T05 → T07 → T08; T09 → T11; T10 independent.

## Implementation Strategy

MVP = T01-T06 (mapping, foldover rules and the applied transform); then the editor and persistence (T07-T11). T12 needs the owner's device.
