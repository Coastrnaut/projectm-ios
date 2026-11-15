# Tasks: OUT-014 Output Profile Export

**Input**: design documents in `specs/288-out-014-output-profile-export/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the brief and spec (pure, app, leak, UI). Budgets: owner rule 7.

## Phase 1: Setup

- [X] OUT-014-T01 Create simulator "OUT14 iPhone 17" (iOS 27.2) and run `xcodegen generate` in the worktree — Verified 2026-11-15: simulator 871D2B57 created; `xcodegen generate` OK

## Phase 2: Foundational (C1)

- [X] OUT-014-T02 Add `OutputProfile`, `OutputProfile.Calibration` ("gamma 0.5…2.5, trims 0.5…1.5, finite"), `OutputDisplayClass` ("nativeWidth/Height ≥ 1, ≤ 32768; pixelAspect 0.5…2; refreshRate 1…1000 when present; gamut sRGB or displayP3 when present"), `OutputDisplayClassMatch`, `OutputProfileDocument` (format `org.projectmios.output-profile`, version 1, `.pmoutput`, max 16384 bytes, sorted-key JSON, no unknown or missing field, "percent integer in 50…100", corner pin `CornerPin.isValid`) and `OutputProfileImportError` in Packages/PresentationLifecycle/Sources/PresentationLifecycle/OutputProfile.swift — Verified 2026-11-15: `swift test` PresentationLifecycle 120 tests pass (0.26 s)
- [X] OUT-014-T03 [P] Pure tests: round trip of every field bit for bit (with and without display); version checks (newer → `newerVersion`, 0 → `notAProfile`); invalid files change nothing (bow-tie pin, out-of-range calibration, truncated, oversized, unknown field, missing field, bad enum, fractional percent); display-class match (same, different size/aspect/gamut, refresh ignored, unknown) in Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/OutputProfileTests.swift — Verified 2026-11-15: OutputProfileTests 6/6 pass on the Mac host

## Phase 3: User Story 1 — export (P1)

**Independent test**: custom settings + stand-in display → exported document holds every value and the class; no identifiers.

- [X] OUT-014-T04 [US1] `ExternalDisplayCoordinator.outputDisplayClass` (OUT-011 readings + the slot's screen pixel aspect) in Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift — Verified 2026-11-15: OutputProfileAppTests (the class is read from the 1920 × 1080 and 1280 × 720 stand-ins; the file carries 1920)
- [X] OUT-014-T05 [US1] `ExternalOutputSetting.outputProfile(display:)` and `apply(_:)`; `profiles` coordinator property in Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting+Profile.swift and Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift — Verified 2026-11-15: OutputProfileAppTests.testRoundTripOnTheSameDisplayClassReproducesTheOutputWithoutAWarning (every setting equal after apply; keys persisted)
- [X] OUT-014-T06 [US1] `OutputProfileCoordinator` export (temporary file, file mover, removal on every outcome, DEBUG simulation) in Apps/projectM-iOS/Coordinators/OutputProfileCoordinator.swift — Verified 2026-11-15: OutputProfileAppTests (mover requested, temporary folder removed on cancel and success); UI test export in simulation
- [X] OUT-014-T07 [US1] Rows "Export output profile…", "Import output profile…", status line, mover/importer, confirmation dialog in Apps/projectM-iOS/Views/OutputProfileRows.swift; add to Apps/projectM-iOS/Views/ExternalDisplaySection.swift — Verified 2026-11-15: OutputProfileUITests taps both rows and reads `outputProfileMessage`; build with type-check warnings flags shows none in the new code

## Phase 4: User Story 2 — import on the same / different class (P1)

**Independent test**: export, reset, import on the stand-in: values, `sublayerTransform` and calibration equal the originals; different class warns.

- [X] OUT-014-T08 [US2] Import: security-scoped read of at most 16 KB + 1, decode, match, apply or hold as pending; Apply Anyway / Cancel in Apps/projectM-iOS/Coordinators/OutputProfileCoordinator.swift — Verified 2026-11-15: OutputProfileAppTests 6/6 pass on iOS 27.2 simulator (0.11 s): same class applies, different class pending → Cancel / Apply Anyway, unknown applies unchecked
- [X] OUT-014-T09 [US2] App acceptance tests (round trip on the stand-in without warning; 1280 × 720 stand-in warns, Cancel changes nothing, Apply Anyway applies; no display connected applies with the "could not be checked" message (OUT-014-R9); export then cancel leaves no temporary file (OUT-014-R4); calibration ranges equal `DisplayCalibration`'s; leak test: no device name, identifierForVendor, display id, UUID, IPv4 or MAC in the file; no new UserDefaults keys) in Apps/projectM-iOS/Tests/OutputProfileAppTests.swift — Verified 2026-11-15: OutputProfileAppTests 6/6 pass (round trip: `sublayerTransform` and slot calibration equal; 1280 × 720 warns; leak test; ranges equal DisplayCalibration; only `settings.externalDisplay.*` keys written)

## Phase 5: User Story 3 — bad files (P2)

- [X] OUT-014-T10 [US3] App test: an invalid document through the coordinator leaves every setting and the external slot unchanged and shows the reason, in Apps/projectM-iOS/Tests/OutputProfileAppTests.swift — Verified 2026-11-15: OutputProfileAppTests.testInvalidFilesChangeNothing (bow tie, calibration out of range, truncated, empty: setting and slot unchanged)

## Phase 6: Polish

- [X] OUT-014-T11 UI test with `-uitestOutputProfileSimulation` and the fake display: export, reset calibration in its editor, import, `externalCalibration` probe shows the exported values, message "Applied output profile." (under 30 s) in Apps/projectM-iOS/UITests/OutputProfileUITests.swift — Verified 2026-11-15: OutputProfileUITests 1/1 pass in 29.3 s warm (54.9 s on the first run, which booted the simulator)
- [X] OUT-014-T12 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), type-check budget, privacy manifest and network symbols on the Debug app, `LibraryBackupAppTests` and `SettingsTests`; delete the simulator and derived data — Verified 2026-11-15: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 179 OK; check_privacy_manifest and check_network_symbols OK on the Debug app; LibraryBackupAppTests, SettingsTests, CornerPinAppTests, DisplayCalibrationAppTests, OutputDiagnosticsAppTests 22/22 pass; no new UserDefaults keys; simulator and derived data deleted
- [ ] OUT-014-T13 {device} On D1 with a projector: export, reset, import reproduces the pin and calibration with no warning; another display warns (quickstart B)

## Dependencies

T01 → T02 → T03; T02 → T04-T08 → T09-T11; all → T12. T13 needs a person and a projector.

## Parallel examples

T03 alongside T04/T05 (different files). T09/T10 and T11 build once, run separately.

## Implementation strategy

MVP = Phases 2-4 (the roadmap acceptance). US3's rules live in C1 already; T10 proves them in the app.

## Analyze (2026-11-15)

speckit-analyze: 0 critical, 0 high. Applied: C1 (MEDIUM) OUT-014-R9's unknown-class path had no test → added to
T09; C2 (MEDIUM) R4's "removes its temporary copy" had no assertion → added to T09. Noted, not changed: E1 (LOW) the
recording-hold edge case reuses the setting's existing behaviour (covered by OUT-003/004/007/009 tests). Coverage
R1-R10: 100 % (R1 T07; R2 T02, T05, T06; R3 T09; R4 T06, T09; R5 T02, T08; R6 T08, T10; R7 T05, T08, T09; R8 T08, T09;
R9 T08, T09; R10 T03, T09). Constitution: no conflict.
