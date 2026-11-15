# Tasks: OUT-006 Output Mirroring Toggle

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/output-mode.md](contracts/output-mode.md), [quickstart.md](quickstart.md)

Tests are requested by the row's acceptance and the brief. Budgets (owner rule 7): unit ≤ 10 s, UI < 30 s.

## Phase 1: Foundational

- [ ] OUT-006-T01 [P] Add `ExternalOutputMode` (`sameScene` default, `clean`; "Unknown or missing → `sameScene`"), `OutputLayerClass` and `OutputLayerRouting` (C1) in Packages/PresentationLifecycle/Sources/PresentationLifecycle/ExternalOutputMode.swift
- [ ] OUT-006-T02 [P] Package tests for the rule table and stored-value reading in Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/ExternalOutputModeTests.swift

## Phase 2: User Story 1 - A clean picture on the projector (P1)

**Independent test**: with a logo layer attached and the stand-in display, the layer's effective opacity follows the mode only while the visual is external.

- [ ] OUT-006-T03 [US1] `outputMode`, `routesSceneOverlays`, `onSceneOverlaysChange`, `outputModeSummary`, evaluated in `place()` and the mode setter (C2; OUT-006-R2, R3, R5) in Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift
- [ ] OUT-006-T04 [US1] `outputSuppressed` and `effectivePlacement` pushed to every attached and newly attached logo layer, stored placement unchanged (C3) in Apps/projectM-iOS/Coordinators/LogoCoordinator.swift
- [ ] OUT-006-T05 [US1] Wire the callback to `logo.outputSuppressed` and apply the stored mode at launch in Apps/projectM-iOS/Coordinators/AppCoordinator+ExternalDisplay.swift

## Phase 3: User Story 2 - One audio capture whatever the mode (P1)

- [ ] OUT-006-T06 [US2] Acceptance test: real `AppCoordinator` + stand-in display; toggle the mode; assert routing (external slot holds only the visual, overlays shown/hidden, logo layer opacity 0/stored) and that `manager`, `normalizedOutput`, `analysisTap` identities, state, transition count are unchanged; plus coordinator-level tests (device target always shows overlays, disconnect restores, live while a recording holds; OUT-006-R2 to R6, S1, S2, S4) in Apps/projectM-iOS/Tests/ExternalOutputModeAppTests.swift

## Phase 4: User Story 3 - The setting persists (P2)

- [ ] OUT-006-T07 [US3] `outputMode` stored under `settings.externalDisplay.outputMode` in `ExternalOutputSetting.keys`, strings, footer (C4; OUT-006-R1, R7, S3) in Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift; Output picker `externalOutputModePicker` in Apps/projectM-iOS/Views/ExternalDisplaySection.swift; persistence test in Apps/projectM-iOS/Tests/ExternalOutputModeAppTests.swift
- [ ] OUT-006-T08 [US3] Key lists: `ALLOWED_KEYS` in scripts/run_device_tests.py, `excludedKeys` in Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, `externalDisplayKeys` in Packages/LibraryBackup/Sources/LibraryBackup/LibraryErasePolicy.swift (LibraryBackupAppTests reads `ExternalOutputSetting.keys`)

## Phase 5: Polish

- [ ] OUT-006-T09 DEBUG probe `externalOutputMode` (C5; OUT-006-R8) in Apps/projectM-iOS/Debug/UITestExternalDisplay.swift and UI test in Apps/projectM-iOS/UITests/ExternalOutputModeUITests.swift (< 30 s); run the repo checks, LibraryBackupAppTests, SettingsTests, ExternalDisplayCoordinatorTests
- [ ] OUT-006-T10 {device} D1 with a real external display, a logo and the Photo visual: quickstart B (Clean hides the logo on the display at once, audio uninterrupted, disconnect restores it)

## Dependencies

T01 → T03 → T05 → T06; T04 → T05; T07 → T09; T08 independent. T01/T02 and T04 in parallel.

## Implementation Strategy

MVP = T01-T06 (routing + acceptance proof); then persistence and UI (T07-T09). T10 needs the owner's device.
