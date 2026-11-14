# Tasks: FILE-006 Incremental Backup Manifest

**Input**: Design documents from `specs/139-file-006-incremental-backup/`

**Tests**: Requested by the roadmap row (schema and fixture tests plus the simulator). Budgets
(owner rule 7): unit tests about 1-2 s (at most 10 s), package suite under 1 minute, UI test under
30 s.

## Phase 1: Foundational

- [X] FILE-006-T01 `BackupFolderManifest`, `AssetEntry`, layout constants, bounded reader and deterministic encoding in Packages/LibraryBackup/Sources/LibraryBackup/BackupFolderManifest.swift (contract B1, research D5; FILE-006-R2, R5) — Verified 2026-11-14: FolderBackupManifestTests 4/4 (host, `swift test --package-path Packages/LibraryBackup`)
- [X] FILE-006-T02 `BackupFileAccess` (status, digest, copy with hashing; CryptoKit guarded, portable hasher on Linux) and `LocalBackupFileAccess` in BackupFileAccess.swift (contract B2, research D3, D7; FILE-006-R10, R11) — Verified 2026-11-14: FolderBackupAcceptanceTests via CountingFileAccess; FolderBackup*/MediaRestore 22/22 also with `-Xswiftc -DLIBRARYBACKUP_NO_CRYPTOKIT` (portable hasher, the Linux path) on the host; the Linux CI job itself is left to CI
- [X] FILE-006-T03 `MediaBackupInventory` (photos and videos via FILE-008 logical files, audio assets, audio index; content address from the stored name) in MediaBackupInventory.swift (contract B3) — Verified 2026-11-14: FolderBackupAcceptanceTests (5 assets found: video payload, photo payload, legacy photo, audio asset, audio index)
- [X] FILE-006-T04 Schema tests: valid manifest round trip; oversized, malformed, wrong format, unknown version, bad kind/name/location, hash-location mismatch and duplicate entries read as unusable; an entry without a hash reads (migration) in Packages/LibraryBackup/Tests/LibraryBackupTests/FolderBackupManifestTests.swift (FILE-006-R2, R5) — Verified 2026-11-14: FolderBackupManifestTests 4/4: round trip with equal bytes, hashless entry reads, 11 unusable cases, layout

## Phase 2: User Story 1 - A second backup copies nothing that did not change (P1)

- [X] FILE-006-T05 [US1] `FolderBackupWriter` (decide unchanged, copy with hash, one copy per content, archive, manifest, prune; fault hook per step) and `FolderBackupLayout` in FolderBackupWriter.swift (contract B4, research D2-D4; FILE-006-R3, R4, R6, R7) — Verified 2026-11-14: FolderBackupAcceptanceTests 5/5 and FolderBackupSafetyTests 8/8 pass on the host
- [X] FILE-006-T06 [US1] Acceptance test: fixture library with a 4 MiB fake video, two photos (one legacy copy, one payload), an audio asset and index; second backup reads 0 bytes from every media file (IO-counting access), copies nothing, equal entries; one photo changed → exactly it hashed and copied; one asset deleted → its copy pruned; two references to one payload → one copy, in FolderBackupAcceptanceTests.swift (FILE-006-S1, S2) — Verified 2026-11-14: FolderBackupAcceptanceTests.testASecondBackupDoesNotRereadTheVideoOrAnyUnchangedAsset: 0 bytes read from the 4 MiB video and from every file, 0 copies, equal entries; changed photo, re-import, deletion and shared payload tests pass

## Phase 3: User Story 2 - A damaged or interrupted backup is never trusted (P1)

- [X] FILE-006-T07 [US2] Corrupt, unknown-version and crafted manifests give a full backup; a fault at each copy, the archive and the manifest leaves the previous manifest with every named file present and matching its hash, and the next backup collects leftovers; a FILE-005-only folder and a hashless manifest (migration) get a full pass; a truncated copy is recopied; prune never touches files outside `media/` or not matching the pattern, in FolderBackupSafetyTests.swift (FILE-006-S3; FILE-006-R5, R6, R7) — Verified 2026-11-14: FolderBackupSafetyTests 8/8: corrupt/newer/empty and crafted manifests give full backups; faults at copy (2), archive, manifest and prune keep the previous manifest consistent; migration; truncation; foreign files kept

## Phase 4: User Story 3 - Media come back from the folder (P2)

- [X] FILE-006-T08 [US3] `MediaRestoreStager`, `MediaRestoreRequestStore`, `MediaRestoreLaunch` in MediaRestore.swift (contract B5, research D6; FILE-006-R8) — Verified 2026-11-14: MediaRestoreTests 5/5 on the host
- [X] FILE-006-T09 [US3] Round trip into an empty root (every photo/video identifier resolves to equal bytes, audio assets and index equal); an identifier already on the device stays; audio skipped when the device has an index; a tampered copy refuses with nothing staged; an interrupted install reruns; newer request ignored, in MediaRestoreTests.swift (FILE-006-S4) — Verified 2026-11-14: MediaRestoreTests 5/5: round trip byte for byte, device files and audio kept, tampered and missing copies refused with nothing staged, interrupted install reruns, newer request removed, cancel

## Phase 5: User Story 4 - App (P2)

- [X] FILE-006-T10 [US4] `FolderBackupCoordinator` (backup and restore off the main thread under the folder's security scope; summary text; pending state; result once; mutual exclusion with FILE-005 restore and FILE-011 erase) and the launch hook in LibraryBackupCoordinator.swift, in Apps/projectM-iOS/Coordinators/FolderBackupCoordinator.swift (contract B6; FILE-006-R1, R8, R9) — Verified 2026-11-14: FolderBackupAppTests 4/4 on the own iOS 27.2 simulator FILE6
- [X] FILE-006-T11 [US4] Backup section rows, folder picker and footer in Apps/projectM-iOS/Views/LibraryBackupSection.swift; DEBUG `-uitestBackupFolder`, `-uitestMediaRestoreFrom`, `-uitestMediaSeed` (FILE-006-R1, R9) — Verified 2026-11-14: FolderBackupUITests 1/1 (10.2 s) on FILE6; LibraryBackupUITests and LibraryEraseUITests still pass
- [X] FILE-006-T12 [US4] App unit tests: summary text; backup then stage then launch install into a temp root; refused while a restore or erase is pending, in Apps/projectM-iOS/Tests/FolderBackupAppTests.swift — Verified 2026-11-14: FolderBackupAppTests 4/4 (summary, second backup unchanged, staged restore installed at launch with the result once, erase exclusion both ways); LibraryBackupAppTests 5/5, LibraryEraseAppTests 3/3
- [X] FILE-006-T13 [US4] UI test: seeded media, two folder backups in one launch; the second reports "0 copied" and the assets unchanged, in Apps/projectM-iOS/UITests/FolderBackupUITests.swift (FILE-006-S5) — Verified 2026-11-14: FolderBackupUITests.testASecondFolderBackupReportsTheMediaUnchanged passed (10.2 s): "2 copied" then "0 copied, 2 unchanged"

## Phase 6: Polish

- [X] FILE-006-T14 ADR (folder backup format, change detection, prune and restore rules); privacy policy line; spec status; repo checks (compliance, docs, motion, permission catalog, status events, scripts, privacy manifest, network symbols); type-check budget (FILE-006-R10, R11) — Verified 2026-11-14: ADR-0052, privacy policy; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events exit 0; test_scripts 153 OK; check_privacy_manifest and check_network_symbols OK on the Debug app; no type-check warnings in the changed files (-warn-long-function-bodies=300, -warn-long-expression-type-checking=150)

## Dependencies

T01-T03 → T04, T05 → T06, T07 → T08 → T09 → T10 → T11 → T12, T13 → T14.
