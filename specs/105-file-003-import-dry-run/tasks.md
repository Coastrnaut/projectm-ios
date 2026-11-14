# Tasks: FILE-003 Import Dry Run

**Input**: Design documents from `specs/105-file-003-import-dry-run/`

**Tests**: Requested by the roadmap row (schema and fixture tests plus the simulator). Budgets
(owner rule 7): unit tests about 1-2 s (at most 10 s), package suite under 1 minute, UI test under
30 s.

## Phase 1: Setup

- [X] FILE-003-T01 Add `LibraryTreeSnapshot` (relative path → SHA-256 of every file, every directory, `digest`) in Packages/PresetLibrary/Sources/PresetLibrary/LibraryTreeSnapshot.swift with tests in Packages/PresetLibrary/Tests/PresetLibraryTests/LibraryTreeSnapshotTests.swift (a changed byte, an added empty folder and a removed file each change the snapshot) — Verified 2026-11-14: LibraryTreeSnapshotTests (4 tests) pass, `swift test --package-path Packages/PresetLibrary`

## Phase 2: Foundational

- [X] FILE-003-T02 Add the plan types (`PresetArchiveConflictPolicy` keepBoth default/skip, `PresetArchiveEntryKind`, `PresetArchiveRefusal`, `PresetArchivePlanEntry`, `PresetArchiveAction`, `PresetArchiveImportPlan` with counts, missingLicense, totalBytes, actions) and the pure `PresetArchiveImportPlanner.plan` following contract C1's classification order and research FILE-003-D3's deterministic identifiers in Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/PresetArchiveImportPlan.swift — Verified 2026-11-14: PresetArchiveImportPlanTests (11 tests) pass
- [X] FILE-003-T03 Add `UserPresetStore.addAll` (stage in `Staging/`, verify SHA-256, move into `Files/`, index once, full rollback; `fileOperationFault` test hook on `perform`; `load` removes a leftover `Staging/`) in Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/UserPresetStore.swift — Verified 2026-11-14: PresetArchiveInstallTests fault loop (9 injected faults) and leftover-staging test pass

## Phase 3: User Story 1 - Preview a preset archive (P1)

**Goal**: An archive gives exact counts, conflicts, refusals, missing licences and size; Install adds exactly the plan.

**Independent Test**: the fixture table.

- [X] FILE-003-T04 [P] [US1] Fixture builder (archives written with `UserPresetArchiveWriter`; library seeding) in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetArchiveFixtures.swift — Verified 2026-11-14: used by the 18 FILE-003 package tests
- [X] FILE-003-T05 [US1] Fixture table of exact plans: clean, conflicting names, identical content, missing licence, malformed entry, newer format version, oversize (plus ID conflict, quarantined text, built-in, blocked, fails checks, library full, skip policy) in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetArchiveImportPlanTests.swift — Verified 2026-11-14: PresetArchiveImportPlanTests 11/11 pass (7 roadmap fixtures plus ID conflict, refusals, library full, words)
- [X] FILE-003-T06 [US1] `UserPresetLibrary.planArchiveImport` and `installArchive` (C2) in Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/UserPresetLibrary.swift; test that Install executes exactly the plan (ids, names, pending, texts) in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetArchiveInstallTests.swift — Verified 2026-11-14: testInstallAddsExactlyThePlannedPresetsAsWaiting passes
- [X] FILE-003-T07 [US1] Coordinator: `.zip` routing, `previewArchive`, `setArchivePolicy`, `installArchive`, `cancelArchive`, announcements on the `library` lane (add the lane in Apps/projectM-iOS/Coordinators/AccessibilityAnnouncer.swift) in Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift; wiring in Apps/projectM-iOS/Coordinators/AppCoordinator.swift — Verified 2026-11-14: PresetArchiveImportAppTests 5/5 pass on the iOS 27.2 simulator (library-lane announcements asserted); Debug build with no warnings in touched files
- [X] FILE-003-T08 [US1] Preview sheet in Apps/projectM-iOS/Views/PresetArchiveImportView.swift and its presentation plus `.zip` picker type in Apps/projectM-iOS/Views/UserPresetsView.swift (C4 identifiers; small bodies; accessibility sizes; no animation, so `check_motion_policy.py` has nothing to route) — Verified 2026-11-14: PresetArchiveImportUITests passes at accessibility XXXL (Install and Cancel hittable; screenshot attached); check_motion_policy OK
- [X] FILE-003-T09 [US1] App unit tests (preview, install, announcements, words) in Apps/projectM-iOS/Tests/PresetArchiveImportAppTests.swift — Verified 2026-11-14: PresetArchiveImportAppTests 5/5 pass

## Phase 4: User Story 2 - Cancel changes nothing (P1)

**Independent Test**: snapshots before and after.

- [X] FILE-003-T10 [US2] Byte-for-byte tests: for each fixture, dry run then cancel leaves `LibraryTreeSnapshot` of `UserPresets` and `PresetCollections` identical; an install failing at every fault point leaves it identical, in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetArchiveInstallTests.swift — Verified 2026-11-14: testDryRunThenCancelLeavesTheLibraryByteForByteUnchangedForEveryFixture (7 fixtures x 2 policies) and testAnInstallFailingAtEveryFileOperationLeavesTheLibraryUnchanged pass
- [X] FILE-003-T11 [US2] DEBUG probes (`libraryDigest`, `archiveDigestAtPreview`) and the `-uitestPresetArchiveFixture` hook in Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift and Apps/projectM-iOS/Coordinators/AppCoordinator.swift; UI test at the largest accessibility text size (preview, Install and Cancel hittable, Cancel, same digest, fixture preset not listed; under 30 s) in Apps/projectM-iOS/UITests/PresetArchiveImportUITests.swift — Verified 2026-11-14: PresetArchiveImportUITests.testCancelLeavesTheLibraryUnchanged passes in 14.6-19.8 s (non-empty digest equal before and after Cancel, seeded preset still listed)
- [X] FILE-003-T12 [US2] App test: coordinator preview then cancel leaves the library folder snapshot identical and every UserDefaults key whose name contains "preset" or "collection" unchanged (the preset screens own no key today; analyze finding C2), in Apps/projectM-iOS/Tests/PresetArchiveImportAppTests.swift — Verified 2026-11-14: testPreviewThenCancelLeavesTheLibraryByteForByteUnchanged passes

## Phase 5: User Story 3 - Conflict policy (P2)

- [X] FILE-003-T13 [US3] Keep both installs "<name> copy" under the D3 id and leaves the existing preset byte-identical; Skip installs neither, in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetArchiveInstallTests.swift — Verified 2026-11-14: testKeepBothLeavesTheExistingPresetUntouchedAndSkipInstallsNothing passes

## Phase 6: User Story 4 - Library changed meanwhile (P2)

- [X] FILE-003-T14 [US4] Re-validation: a preset removed or added between plan and install gives `.changed(newPlan)` with nothing written, in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetArchiveInstallTests.swift — Verified 2026-11-14: testALibraryChangedAfterThePreviewIsDetectedWithNothingWritten passes

## Phase 7: User Story 5 - Scene archive plan (P3)

- [X] FILE-003-T15 [US5] `SceneArchivePlan`/`planImport(at:)` and `importArchive(at:plan:)` with `.planChanged` in Apps/projectM-iOS/Coordinators/SceneArchiveService.swift — Verified 2026-11-14: SceneArchiveImportPlanTests 4/4 pass
- [X] FILE-003-T16 [US5] Tests: plan of a photo+video archive (media, replaces, repair entries, empty licences, size, steps), refusals (tampered, newer scene version, oversize), dry run leaves the stores' folders and keys identical, install executes the plan's steps, changed store refused, in Apps/projectM-iOS/Tests/SceneArchiveImportPlanTests.swift — Verified 2026-11-14: SceneArchiveImportPlanTests 4/4 pass (plan, plan-checked steps, changed store, tampered/newer version/oversize refusals with stores unchanged)

## Phase 8: Polish

- [X] FILE-003-T17 Run the checks (compliance, docs, motion policy, permission catalog, status events, script tests, privacy manifest on the Debug app), the PresetLibrary suite on the host and in Linux shape, and the app tests and UI tests listed in quickstart.md; record results in spec.md's status — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 151 OK (1 skipped); check_privacy_manifest OK on the Debug app; PresetLibrary 230 tests on the macOS host; projectM-iOSTests 461 and UI tests UserPresetsUITests 3, UserPresetExportUITests 2, PresetArchiveImportUITests 1 on the FILE3 iOS 27.2 simulator; PosterBoard reports 25 before and after. Linux container run not available on this Mac (CI's Linux job covers it)

## Dependencies

T01 → T02 → T03 → US1 (T04-T09) → US2 (T10-T12); US3 and US4 need T06; US5 is independent of
US1-US4 (only T01 for snapshots in app tests). T17 last.

## Parallel examples

- T04 and T15 (different packages and files).
- T08 and T09 once T07 is done.

## Implementation strategy

MVP: T01-T06 and T10 (planner, atomic install, byte-for-byte proof in the package). Then the app
flow (T07-T09, T11-T12), the policy and re-validation tests, the scene plan, and the checks.
