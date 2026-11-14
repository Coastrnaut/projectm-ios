# Tasks: FILE-005 Local Library Backup

**Input**: Design documents from `specs/114-file-005-local-library-backup/`

**Tests**: Requested by the roadmap row (schema and fixture tests plus the simulator). Budgets
(owner rule 7): unit tests about 1-2 s (at most 10 s), package suite under 1 minute, UI test under
30 s.

## Phase 1: Setup

- [ ] FILE-005-T01 Create Packages/LibraryBackup (Package.swift with LocalPortability, PresetLibrary, ShowControl, SceneFormat; one library product), add it to project.yml (package and app dependency) and to every package list in .github/workflows/ios-ci.yml

## Phase 2: Foundational

- [ ] FILE-005-T02 Format, limits, manifest, errors and migration table in Packages/LibraryBackup/Sources/LibraryBackup/LibraryBackupFormat.swift; folders in LibraryFolders.swift; typed setting values and the included keys in LibrarySettings.swift (contract C1, C2; data-model)
- [ ] FILE-005-T03 `LibraryContents` and `LibraryContentsReader` (reads the five folders and a settings dictionary; applies the exclusions; counts them) in LibraryContents.swift (research D7)
- [ ] FILE-005-T04 `LibraryRecords`: the logical-equality function with `differences` in LibraryRecords.swift (FILE-005-R9, research D2)

## Phase 3: User Story 1 - Back up the library (P1)

- [ ] FILE-005-T05 [US1] `LibraryBackupWriter` and `LibraryBackupReader` (limits, record decoding, cross-checks) in LibraryBackupArchive.swift (contract C1, C2)
- [ ] FILE-005-T06 [US1] Package tests: manifest shape and counts, deterministic bytes, exclusions (no full-library copy, quarantined text, video, audio, device keys, entitlement), an empty library in Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupWriterTests.swift (FILE-005-S5)

## Phase 4: User Story 2 - Restore on a fresh sandbox (P1)

- [ ] FILE-005-T07 [US2] `LibraryRestorePlanner` (pure; exact into empty stores, FILE-004 scene plan otherwise; choices, fallbacks, derived IDs, limits) in LibraryRestorePlan.swift (contract C4, research D5)
- [ ] FILE-005-T08 [US2] `LibraryRestoreInstaller` (staging, journal, swap, settings after commit, recovery, fault hook) in LibraryRestoreInstaller.swift (contract C5, research D4)
- [ ] FILE-005-T09 [US2] The acceptance test: every record kind in a temp sandbox, back up, restore into an empty sandbox, `LibraryRecords` equal for every record; restored presets pending; in LibraryBackupRoundTripTests.swift (FILE-005-S1)

## Phase 5: User Story 3 - Restore over an existing library (P2)

- [ ] FILE-005-T10 [US3] Package tests for each choice over clashing scenes, presets, collections, settings, favorites and photos; deterministic plans; limits refused, in LibraryRestoreChoiceTests.swift (FILE-005-S3)

## Phase 6: User Story 4 - Nothing half-restored (P1)

- [ ] FILE-005-T11 [US4] Package tests: a fault at every file operation leaves the snapshot identical; interrupted prepared/committed journals recovered; a changed library returns a new plan; in LibraryRestoreFaultTests.swift (FILE-005-S2)

## Phase 7: User Story 5 - Damaged files refused (P1)

- [ ] FILE-005-T12 [US5] Package tests: truncated, corrupted, tampered, foreign, newer-version, oversize, unsafe-path, mismatched-scene-ID and excluded-record archives refused, and a backup holding an older-version scene read through SCN-013 migration, in LibraryBackupHostileTests.swift; an ImportFuzz suite Packages/ImportFuzz/Tests/ImportFuzzTests/LibraryBackupFuzzTests.swift with seeds made by the writer (FILE-005-S4)

## Phase 8: App

- [ ] FILE-005-T13 Request store and launch runner (`LibraryRestoreRequestStore`, `LibraryRestoreLaunch`) in LibraryRestoreRequest.swift with package tests (contract C6)
- [ ] FILE-005-T14 App: LibrarySettingsBridge.swift (UserDefaults ↔ values), LibraryBackupCoordinator.swift (back up, preview, request, cancel, result, `library` announcements, DEBUG `-uitestBackupTo`/`-uitestRestoreFrom`), the launch hook in AppCoordinator.swift, LibraryBackupSection.swift in StorageUsageView, pass-through in SettingsView/VisualizerView (contract C7, FILE-005-R4-R6, R12)
- [ ] FILE-005-T15 App tests Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift: the key list matches the stores' constants and folder names, the settings bridge round-trips every type, backup and preview through the coordinator, the temporary file is removed, the result is announced on the `library` lane
- [ ] FILE-005-T16 UI test Apps/projectM-iOS/UITests/LibraryBackupUITests.swift: back up a seeded library to a test folder, request its restore, relaunch with a reset library, records back; under 30 s per test (FILE-005-S6)

## Phase 9: Polish

- [ ] FILE-005-T17 ADR docs/adr/0040-local-library-backup.md (format and exclusions), privacy-policy sentence (docs/privacy-policy.md), docs index updates
- [ ] FILE-005-T18 Checks: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events, test_scripts, check_privacy_manifest and check_network_symbols on the built Debug app; Linux shape; PosterBoard count; spec status

## Dependencies

T01 → T02 → T03/T04 → T05 → T06; T05 → T07 → T08 → T09-T11; T05 → T12; T08 → T13 → T14 → T15/T16; T17-T18 last.
