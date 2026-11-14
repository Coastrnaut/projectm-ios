# Tasks: FILE-011 Local Data Erase

**Input**: Design documents from `specs/120-file-011-local-data-erase/`

**Tests**: Requested by the roadmap row (schema and fixture tests plus the simulator). Budgets
(owner rule 7): unit tests about 1-2 s (at most 10 s), package suite under 1 minute, UI test under
30 s.

## Phase 1: Foundational

- [X] FILE-011-T01 Categories, folders, setting keys and never-erased keys in Packages/LibraryBackup/Sources/LibraryBackup/LibraryErasePolicy.swift (contract E1, research D4, D7) — Verified 2026-11-14: LibraryEraseAcceptanceTests.testThePolicyClassifiesEveryKeyOnceAndNamesOnlyLibraryFolders; LibraryEraseAppTests.testFoldersAndKeysAgreeWithTheStores
- [X] FILE-011-T02 `LibraryEraseInventory` (counts by the stores' readers, sizes by FILE-009's calculator) in LibraryEraseInventory.swift (contract E2, research D6; FILE-011-R9) — Verified 2026-11-14: LibraryEraseAcceptanceTests.testTheInventoryCountsAndSizesEachCategory (counts 4/5/4/2/1, sizes > 0, settings no size)

## Phase 2: User Story 1 - Erase chosen categories (P1)

- [X] FILE-011-T03 [US1] `LibraryErasePlanner` and `LibraryEraser` (move aside under a journal, commit, settings and media after the commit, delete; fault hook; recover) in LibraryEraser.swift (contract E3-E5, research D2, D3; FILE-011-R4, R5, R6) — Verified 2026-11-14: LibraryEraseAcceptanceTests (4), LibraryEraseFaultTests (5), LibraryEraseReferenceTests (4) pass on the host
- [X] FILE-011-T04 [US1] `LibraryEraseRequestStore`, `LibraryEraseLaunch` and the result note in LibraryEraseRequest.swift (contract E6; FILE-011-R3) — Verified 2026-11-14: LibraryEraseFaultTests (kill rolled back then request reruns; newer/unknown requests; cancel; result read once)
- [X] FILE-011-T05 [US1] The acceptance test: a sandbox with every record kind, a fake bundle folder, a purchase marker and caches; each category alone, then all six; only the chosen records gone (`LibraryRecords`, `LibraryTreeSnapshot`), the rest and the bundle byte-for-byte unchanged; policy disjointness, in Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryEraseAcceptanceTests.swift (FILE-011-S1) — Verified 2026-11-14: LibraryEraseAcceptanceTests 4/4: each of the six categories alone and all six; records, folder snapshots, keys; bundle, purchase marker, caches, tmp and restore folder byte-for-byte unchanged

## Phase 3: User Story 3 - Nothing half-erased (P1)

- [X] FILE-011-T06 [US3] Fault at every file operation before the commit leaves the snapshot identical; after the commit the next launch finishes; a prepared journal is rolled back and the pending request runs again; a newer or unknown request is dropped, in LibraryEraseFaultTests.swift (FILE-011-S2) — Verified 2026-11-14: LibraryEraseFaultTests 5/5: a fault at each of the operations up to the commit leaves snapshots, records and settings identical

## Phase 4: User Story 4 - References stay consistent (P2)

- [X] FILE-011-T07 [US4] Scenes erase releases scene-only photo and video references and keeps the current ones; media erase leaves scenes naming IDs that no longer resolve; no write-back: an autosave tick after the request is gone after the launch erase and a store loaded afterwards reads empty, in LibraryEraseReferenceTests.swift (FILE-011-R8, S3, S4) — Verified 2026-11-14: LibraryEraseReferenceTests 4/4 (scene-only references and payloads released, current and unrelated photos kept; media erase leaves scenes naming unresolvable IDs; no write-back after an autosave tick)

## Phase 5: User Story 2 and 5 - Confirmation, pending state, result (P1/P2)

- [X] FILE-011-T08 [US2] `LibraryEraseCoordinator` (inventory off the main thread, selection, request, cancel, result once, `library` lane, mutual exclusion with a pending restore) owned by LibraryBackupCoordinator; the launch hook runs the erase before the restore; the settings bridge removes keys (FILE-011-R1-R3, R7) — Verified 2026-11-14: LibraryEraseAppTests.testMeasureConfirmRequestCancelAndLaunchErase and testAPendingRestoreBlocksAnEraseAndAPendingEraseBlocksARestore on the FILE11 iOS 27.2 simulator
- [X] FILE-011-T09 [US2] `LibraryEraseSection` and `LibraryEraseSheet` (checkboxes with count and size, Select All, Back Up Library First…, Erase… → destructive confirmation naming the categories) in Apps/projectM-iOS/Views/LibraryEraseSection.swift, one line in StorageUsageView.swift (FILE-011-R1, R2, R10) — Verified 2026-11-14: LibraryEraseUITests on the FILE11 iOS 27.2 simulator; build with -warn-long-function-bodies=300 / -warn-long-expression-type-checking=150 reports nothing in the new files
- [X] FILE-011-T10 [US2] App tests: policy folders and keys agree with the stores and FILE-005's lists; coordinator request, cancel, launch erase removes keys and folders, result once and announced; confirmation text names the categories; Erase Data… refused while a restore is pending; after a launch erase the stores (presets, collections, show) load as empty with no error (FILE-011-R7), in Apps/projectM-iOS/Tests/LibraryEraseAppTests.swift — Verified 2026-11-14: projectM-iOSTests 550/550 on the FILE11 iOS 27.2 simulator, LibraryEraseAppTests 3/3
- [X] FILE-011-T11 [US2] UI test: seeded show; the confirmation names the category; Cancel records nothing; Erase at Next Launch, relaunch, the result is shown and the show's records are gone, in Apps/projectM-iOS/UITests/LibraryEraseUITests.swift (FILE-011-S5) — Verified 2026-11-14: LibraryEraseUITests 1/1 (24.6 s), with StorageUsageUITests and LibraryBackupUITests passing in the same run

## Phase 6: Polish

- [X] FILE-011-T12 ADR (erase semantics), privacy policy sentence, Storage footer; checks: compliance, docs, motion, permissions, status events, script tests, privacy manifest on the built Debug app; long-body warnings flag — Verified 2026-11-14: ADR-0048; privacy policy section and table row; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 OK; check_privacy_manifest OK on the built Debug app

## Dependencies

T01 → T02, T03 → T04 → T05-T07; T04 → T08 → T09 → T10, T11; T12 last.
