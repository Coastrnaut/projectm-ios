# Tasks: REC-011 Export to Photos

**Input**: `specs/210-rec-011-export-to-photos/` (spec, plan, research, data-model, contracts/photos-save.md, quickstart)
**Tests**: requested by the roadmap acceptance (denial keeps the original and shows an error) and the brief (injected access and saver; no request without the user's tap; a UI test under 30 s).

## Phase 1: Setup (permission set)

- [ ] REC-011-T01 Write ADR-0059 "Photos add-only permission" in docs/adr/0059-photos-add-only-permission.md and list it in docs/adr/README.md (overrides FILE-013's no-Photos-key rule and REC-012-R7's no-permission clause for the add-only key only)
- [ ] REC-011-T02 Add `NSPhotoLibraryAddUsageDescription` (contract C4 text) to the projectM-iOS target in project.yml; allow the add-only key in the app target in scripts/check_permission_catalog.py while `NSPhotoLibraryUsageDescription` stays forbidden; update scripts/test_scripts.py (five keys; full-library key fails; add-only key outside the app target fails)
- [ ] REC-011-T03 Add `AppPermission.photosAdd`, the "Photos (add only)" catalog entry, its denied and restricted notices (contract C3) and the `PermissionExplainerPolicy.key`/explainer switches (no explainer, REC-011-R14) in Apps/projectM-iOS/Coordinators/PermissionCatalog.swift and PermissionExplainer.swift; update Apps/projectM-iOS/Tests/PermissionCatalogTests.swift and CaptureShareAppTests.swift (REC-012-S4 now: share sheet still excludes Save to Photos; only the add-only key exists)
- [ ] REC-011-T04 Add the "Photos (add only)" bullet to "Permissions and why" in docs/privacy-policy.md and update its closing paragraph

## Phase 2: Foundational

- [ ] REC-011-T05 `PhotosAccess`, `PhotosSaveItem`, `PhotosSaveOutcome`, protocols `PhotosAccessProviding` and `PhotosSaving`, the live Photos service (research D1-D4) and `PhotosSaveCoordinator` (data model; contract C2) in Apps/projectM-iOS/Coordinators/PhotosSaveCoordinator.swift
- [ ] REC-011-T06 [P] DEBUG stand-in for `-uitestPhotosAccess granted|denied|restricted|failing` (contract C5) in Apps/projectM-iOS/Debug/PhotosSaveStandIn.swift

## Phase 3: User Story 1 - Save a finished frame or recording (P1) MVP

**Goal**: explicit Save to Photos on both panels and the Recordings rows.
**Independent test**: injected granted access saves exactly once; offers stay.

- [ ] REC-011-T07 [US1] Save to Photos buttons (contract C1), the notice view with Open Settings and Dismiss, and per-item disabling (REC-011-R10) in Apps/projectM-iOS/Views/CaptureResultPanels.swift; one `photosSave` property in Apps/projectM-iOS/Coordinators/AppCoordinator.swift; pass it from Apps/projectM-iOS/Views/VisualizerView.swift
- [ ] REC-011-T08 [US1] Row button, accessibility action and notice row in Apps/projectM-iOS/Views/RecordingLibraryView.swift (photos coordinator held by RecordingLibraryModel, set in AppCoordinator.makeRecordingLibrary)
- [ ] REC-011-T09 [US1] ACC-011 row X8a `photosNotice` in Apps/projectM-iOS/Coordinators/StatusEvents.swift, posted from `CaptureEventChanges` in Apps/projectM-iOS/Views/StatusCaptionView.swift; row in Apps/projectM-iOS/Tests/StatusEventsTests.swift
- [ ] REC-011-T10 [US1] Acceptance tests: granted saves once (frame data and recording URL passed unchanged), not-determined requests once then saves, limited counts as granted, a second tap while saving is ignored, in Apps/projectM-iOS/Tests/PhotosSaveAcceptanceTests.swift

## Phase 4: User Story 2 - Denied or failed save keeps the original (P1)

**Goal**: the roadmap acceptance.
**Independent test**: denied, restricted and failing each leave the recording file byte-identical and offered, with the error notice.

- [ ] REC-011-T11 [US2] Acceptance tests: denied, restricted, failing (and not-determined answered with denied) leave the offered recording file byte-identical at its path, still offered, the frame still offered, the notice text and Open Settings per contract C3, no save call on denial, in Apps/projectM-iOS/Tests/PhotosSaveAcceptanceTests.swift
- [ ] REC-011-T12 [US2] UI test (< 30 s): `-uitestPhotosAccess denied`, record, Save to Photos → notice with Open Settings, "Recording ready" still offered; `granted` → "Saved to Photos." in Apps/projectM-iOS/UITests/PhotosSaveUITests.swift
- [ ] REC-011-T13 [US2] Live simulator check of the real Photos path (not evidence): `simctl privacy grant|revoke photos-add`, UI test gated by `TEST_RUNNER_REC011_LIVE_PHOTOS` in Apps/projectM-iOS/UITests/PhotosSaveUITests.swift

## Phase 5: User Story 3 - No surprise prompts (P1)

- [ ] REC-011-T14 [US3] Acceptance test: creating `PhotosSaveCoordinator` with counting fakes, then a recording offered and kept (REC-010 fixture through `VideoRecordingCoordinator`), and a Recordings refresh make zero `status()`/`request()` calls; plus a source check that `PHPhotoLibrary` appears only in PhotosSaveCoordinator.swift, in Apps/projectM-iOS/Tests/PhotosSaveAcceptanceTests.swift (REC-011-R2, S3)

## Phase 6: Polish

- [ ] REC-011-T15 Repo checks (compliance, validate_docs, motion policy, permission catalog, status events, script tests), `check_privacy_manifest.py` and `check_network_symbols` on the Debug app; type-check budget build; review that no album, conversion, explainer or saved-item record exists (REC-011-R14)
- [ ] REC-011-T16 {device} D1: record, Save to Photos, Allow → video in Photos, recording still offered; save a frame; turn Photos off for projectM in Settings → denied notice, file still offered (quickstart step 5)

## Dependencies

T01-T04 → T05 → T06-T09 → T10-T14 → T15; T16 after integration. US1-US3 share T05; US2 and US3 are tests on the same code.

## Parallel examples

T02, T04 and T06 touch separate files; T10, T11 and T14 live in one test file (one writer).

## Implementation strategy

MVP = Phase 1-3 (the button saves); Phase 4 proves the roadmap acceptance; Phase 5 proves no prompt without the tap.
