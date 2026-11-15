# Tasks: OUT-014 Output Profile Export

**Input**: design documents in `specs/288-out-014-output-profile-export/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the brief and spec (pure, app, leak, UI). Budgets: owner rule 7.

## Phase 1: Setup

- [ ] OUT-014-T01 Create simulator "OUT14 iPhone 17" (iOS 27.2) and run `xcodegen generate` in the worktree

## Phase 2: Foundational (C1)

- [ ] OUT-014-T02 Add `OutputProfile`, `OutputProfile.Calibration` ("gamma 0.5…2.5, trims 0.5…1.5, finite"), `OutputDisplayClass` ("nativeWidth/Height ≥ 1, ≤ 32768; pixelAspect 0.5…2; refreshRate 1…1000 when present; gamut sRGB or displayP3 when present"), `OutputDisplayClassMatch`, `OutputProfileDocument` (format `org.projectmios.output-profile`, version 1, `.pmoutput`, max 16384 bytes, sorted-key JSON, no unknown or missing field, "percent integer in 50…100", corner pin `CornerPin.isValid`) and `OutputProfileImportError` in Packages/PresentationLifecycle/Sources/PresentationLifecycle/OutputProfile.swift
- [ ] OUT-014-T03 [P] Pure tests: round trip of every field bit for bit (with and without display); version checks (newer → `newerVersion`, 0 → `notAProfile`); invalid files change nothing (bow-tie pin, out-of-range calibration, truncated, oversized, unknown field, missing field, bad enum, fractional percent); display-class match (same, different size/aspect/gamut, refresh ignored, unknown) in Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/OutputProfileTests.swift

## Phase 3: User Story 1 — export (P1)

**Independent test**: custom settings + stand-in display → exported document holds every value and the class; no identifiers.

- [ ] OUT-014-T04 [US1] `ExternalDisplayCoordinator.outputDisplayClass` (OUT-011 readings + the slot's screen pixel aspect) in Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift
- [ ] OUT-014-T05 [US1] `ExternalOutputSetting.outputProfile(display:)` and `apply(_:)`; `profiles` coordinator property in Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting+Profile.swift and Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift
- [ ] OUT-014-T06 [US1] `OutputProfileCoordinator` export (temporary file, file mover, removal on every outcome, DEBUG simulation) in Apps/projectM-iOS/Coordinators/OutputProfileCoordinator.swift
- [ ] OUT-014-T07 [US1] Rows "Export output profile…", "Import output profile…", status line, mover/importer, confirmation dialog in Apps/projectM-iOS/Views/OutputProfileRows.swift; add to Apps/projectM-iOS/Views/ExternalDisplaySection.swift

## Phase 4: User Story 2 — import on the same / different class (P1)

**Independent test**: export, reset, import on the stand-in: values, `sublayerTransform` and calibration equal the originals; different class warns.

- [ ] OUT-014-T08 [US2] Import: security-scoped read of at most 16 KB + 1, decode, match, apply or hold as pending; Apply Anyway / Cancel in Apps/projectM-iOS/Coordinators/OutputProfileCoordinator.swift
- [ ] OUT-014-T09 [US2] App acceptance tests (round trip on the stand-in without warning; 1280 × 720 stand-in warns, Cancel changes nothing, Apply Anyway applies; calibration ranges equal `DisplayCalibration`'s; leak test: no device name, identifierForVendor, display id, UUID, IPv4 or MAC in the file; no new UserDefaults keys) in Apps/projectM-iOS/Tests/OutputProfileAppTests.swift

## Phase 5: User Story 3 — bad files (P2)

- [ ] OUT-014-T10 [US3] App test: an invalid document through the coordinator leaves every setting and the external slot unchanged and shows the reason, in Apps/projectM-iOS/Tests/OutputProfileAppTests.swift

## Phase 6: Polish

- [ ] OUT-014-T11 UI test with `-uitestOutputProfileSimulation` and the fake display: export, reset calibration in its editor, import, `externalCalibration` probe shows the exported values, message "Applied output profile." (under 30 s) in Apps/projectM-iOS/UITests/OutputProfileUITests.swift
- [ ] OUT-014-T12 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), type-check budget, privacy manifest and network symbols on the Debug app, `LibraryBackupAppTests` and `SettingsTests`; delete the simulator and derived data
- [ ] OUT-014-T13 {device} On D1 with a projector: export, reset, import reproduces the pin and calibration with no warning; another display warns (quickstart B)

## Dependencies

T01 → T02 → T03; T02 → T04-T08 → T09-T11; all → T12. T13 needs a person and a projector.

## Parallel examples

T03 alongside T04/T05 (different files). T09/T10 and T11 build once, run separately.

## Implementation strategy

MVP = Phases 2-4 (the roadmap acceptance). US3's rules live in C1 already; T10 proves them in the app.
