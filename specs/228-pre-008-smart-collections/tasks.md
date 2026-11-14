# Tasks: PRE-008 Smart Collections

**Input**: Design documents from `specs/228-pre-008-smart-collections/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/smart-collections.md, quickstart.md

Tests are requested by the roadmap acceptance ("Rule changes update membership without duplicate entries").

## Phase 1: Setup

- [X] PRE-008-T01 Create the private simulator "PRE8 iPhone 17" (iOS 27.2) and count PosterBoard reports before any run — Verified 2026-11-14: simulator 2D329711 created on iOS 27.2; PosterBoard reports 26 before

## Phase 2: Foundational (PresetLibrary, Linux-buildable)

- [X] PRE-008-T02 [P] Model, kinds, limits and errors (R1, R2, R6) in Packages/PresetLibrary/Sources/PresetLibrary/Smart/PresetSmartCollection.swift — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary --filter PresetSmartCollectionTests` (4 tests, 0 failures, 0.01 s); full PresetLibrary suite 333 tests, 0 failures (69.7 s on a loaded Mac)
- [X] PRE-008-T03 Matcher (R3, R4; contract C1) in Packages/PresetLibrary/Sources/PresetLibrary/Smart/PresetSmartMatcher.swift — Verified 2026-11-14: `testRuleChangesUpdateMembershipExactlyWithoutDuplicates`, `testEveryKindMatchesAndUnknownKindsAreSkipped` (PresetSmartCollectionTests, 4 tests, 0 failures)
- [X] PRE-008-T04 Document with schema and migration table (R5; C2) in Packages/PresetLibrary/Sources/PresetLibrary/Smart/PresetSmartCollectionsFile.swift — Verified 2026-11-14: `testMigrationNewerAndUnreadableFiles` (injected version-0 step, newer version 2 untouched, repeated IDs set aside, unknown match mode reads All)
- [X] PRE-008-T05 Transactional store (R5, R6; C3) in Packages/PresetLibrary/Sources/PresetLibrary/Smart/PresetSmartCollectionStore.swift — Verified 2026-11-14: `testStoreRoundTripsAndKeepsUnknownKinds` (normalization, duplicate name, 33 conditions refused, reload equal, unknown kind kept through edit)

## Phase 3: User Story 2 - Rule changes update membership exactly (P1)

- [X] PRE-008-T06 [US2] Acceptance (S1): add/remove a tag condition, switch Any/All, add a pack → exact member lists; multi-match, duplicated values, folded spellings and the same hash in two packs appear once; stable order; motion, colour, favorite, not-tag and unknown kinds, in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetSmartCollectionTests.swift — Verified 2026-11-14: `testRuleChangesUpdateMembershipExactlyWithoutDuplicates`: add tag (All) → [Alpha]; Any → [Alpha, Bravo, Charlie] with Alpha once; remove → [Alpha, Charlie]; add packs → Echo (same hash in two packs) once; three re-evaluations equal

## Phase 4: User Story 3 - Kept safely (P2)

- [X] PRE-008-T07 [US3] Store and file tests (S2): round trip, injected migration from version 0, newer unavailable and untouched, unreadable set aside, unknown kind kept through an edit, name and limit refusals, in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetSmartCollectionTests.swift — Verified 2026-11-14: `testStoreRoundTripsAndKeepsUnknownKinds`, `testMigrationNewerAndUnreadableFiles` (0.01 s)
- [X] PRE-008-T08 [US3] FILE-005 record and FILE-011 erase count (R10) in Packages/LibraryBackup/Sources/LibraryBackup/ (LibraryFolders, LibraryBackupFormat, LibraryContents, LibraryBackupArchive, LibraryRecords, LibraryRestorePlan, LibraryRestoreInstaller, LibraryEraseInventory) — Verified 2026-11-14: `swift test --package-path Packages/LibraryBackup` (80 tests, 0 failures, 14.6 s)
- [X] PRE-008-T09 [US3] Backup tests (S3): round trip, restore merge by choice, erase removes the file, in Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupSmartCollectionTests.swift — Verified 2026-11-14: LibraryBackupSmartCollectionTests (3 tests): round trip with equal `smart-collections` digests, Keep both/Replace/identical merge, erase removes and counts the file

## Phase 5: User Story 1 - Save a filter as a smart collection (P1) MVP

- [X] PRE-008-T10 [US1] Coordinator (R7-R9; C4): store wiring, smart memberships merged into the collection scope, titles, fallback, draft count, in Apps/projectM-iOS/Coordinators/PresetCoordinator+Smart.swift, PresetCoordinator.swift and AppCoordinator.swift — Verified 2026-11-14: `PresetSmartCollectionAppTests.testTheScopeWalksMembersAndFollowsTagsAndRuleEdits` on "PRE8 iPhone 17" (iOS 27.2 simulator); PresetCollectionsCoordinatorTests 18 tests still pass
- [X] PRE-008-T11 [US1] Views (R7, R8): Smart Collections section with marker, home Collections row counting manual and smart, detail list with Edit Rules and the unknown-rule note, rule editor with live count, in Apps/projectM-iOS/Views/SmartCollectionViews.swift and PresetCollectionsView.swift — Verified 2026-11-14: build-for-testing succeeds with the type-check flags (no warning in the new or edited files); `PresetSmartCollectionUITests` passes
- [X] PRE-008-T12 [US1] App unit test (S4): the scope walks a smart collection, a tag added later joins it, a rule edit updates it, deletion falls back, in Apps/projectM-iOS/Tests/PresetSmartCollectionAppTests.swift — Verified 2026-11-14: `PresetSmartCollectionAppTests` (2 tests, 0 failures, 0.03 s) on the iOS 27.2 simulator
- [X] PRE-008-T13 [US1] UI test (S5, under 30 s): create a smart collection (Included), see its count, edit rules (add Favorites, All), see the count change, in Apps/projectM-iOS/UITests/PresetSmartCollectionUITests.swift — Verified 2026-11-14: `PresetSmartCollectionUITests.testCreatingASmartCollectionAndEditingItsRulesChangesTheCount` passed (28.2 s warm; 34.4 s on the first launch of a fresh simulator); simulator, not device evidence

## Phase 6: Polish

- [X] PRE-008-T14 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), `LibraryBackupAppTests`, type-check budget, privacy manifest and network symbols on the Debug app — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 174 tests OK (48.9 s); LibraryBackupAppTests 5 tests pass; check_privacy_manifest and check_network_symbols OK on the Debug simulator app; Linux build not run on this host (CI)
- [X] PRE-008-T15 Spec status, PosterBoard count after the runs, delete the simulator and derived data — Verified 2026-11-14: PosterBoard reports 26 before and 26 after; simulator and derived data deleted at the end

## Analysis (speckit-analyze, 2026-11-14)

- Coverage: R1-R6 → T02-T07; R7-R9 → T10-T13; R10 → T08-T09; R11 → T02-T05 (Linux shape checked by the package building with Foundation only).
- Fixed: R1 now says how an unknown match mode reads (data model had it, spec did not); T11 now names the home row count (clarify) and the unknown-rule note (R4).
- No constitution conflicts; no new UserDefaults keys, so the AGENT_RULES key lists are unchanged.

## Dependencies

T02 → T03, T04 → T05 → T06, T07 → T08 → T09; T05 → T10 → T11 → T12, T13; T14, T15 last.
