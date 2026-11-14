# Tasks: FILE-006 Incremental Backup Manifest

**Input**: Design documents from `specs/139-file-006-incremental-backup/`

**Tests**: Requested by the roadmap row (schema and fixture tests plus the simulator). Budgets
(owner rule 7): unit tests about 1-2 s (at most 10 s), package suite under 1 minute, UI test under
30 s.

## Phase 1: Foundational

- [ ] FILE-006-T01 `BackupFolderManifest`, `AssetEntry`, layout constants, bounded reader and deterministic encoding in Packages/LibraryBackup/Sources/LibraryBackup/BackupFolderManifest.swift (contract B1, research D5; FILE-006-R2, R5)
- [ ] FILE-006-T02 `BackupFileAccess` (status, digest, copy with hashing; CryptoKit guarded, portable hasher on Linux) and `LocalBackupFileAccess` in BackupFileAccess.swift (contract B2, research D3, D7; FILE-006-R10, R11)
- [ ] FILE-006-T03 `MediaBackupInventory` (photos and videos via FILE-008 logical files, audio assets, audio index; content address from the stored name) in MediaBackupInventory.swift (contract B3)
- [ ] FILE-006-T04 Schema tests: valid manifest round trip; oversized, malformed, wrong format, unknown version, bad kind/name/location, hash-location mismatch and duplicate entries read as unusable; an entry without a hash reads (migration) in Packages/LibraryBackup/Tests/LibraryBackupTests/FolderBackupManifestTests.swift (FILE-006-R2, R5)

## Phase 2: User Story 1 - A second backup copies nothing that did not change (P1)

- [ ] FILE-006-T05 [US1] `FolderBackupWriter` (decide unchanged, copy with hash, one copy per content, archive, manifest, prune; fault hook per step) and `FolderBackupLayout` in FolderBackupWriter.swift (contract B4, research D2-D4; FILE-006-R3, R4, R6, R7)
- [ ] FILE-006-T06 [US1] Acceptance test: fixture library with a 4 MiB fake video, two photos (one legacy copy, one payload), an audio asset and index; second backup reads 0 bytes from every media file (IO-counting access), copies nothing, equal entries; one photo changed → exactly it hashed and copied; one asset deleted → its copy pruned; two references to one payload → one copy, in FolderBackupAcceptanceTests.swift (FILE-006-S1, S2)

## Phase 3: User Story 2 - A damaged or interrupted backup is never trusted (P1)

- [ ] FILE-006-T07 [US2] Corrupt, unknown-version and crafted manifests give a full backup; a fault at each copy, the archive and the manifest leaves the previous manifest with every named file present and matching its hash, and the next backup collects leftovers; a FILE-005-only folder and a hashless manifest (migration) get a full pass; a truncated copy is recopied; prune never touches files outside `media/` or not matching the pattern, in FolderBackupSafetyTests.swift (FILE-006-S3; FILE-006-R5, R6, R7)

## Phase 4: User Story 3 - Media come back from the folder (P2)

- [ ] FILE-006-T08 [US3] `MediaRestoreStager`, `MediaRestoreRequestStore`, `MediaRestoreLaunch` in MediaRestore.swift (contract B5, research D6; FILE-006-R8)
- [ ] FILE-006-T09 [US3] Round trip into an empty root (every photo/video identifier resolves to equal bytes, audio assets and index equal); an identifier already on the device stays; audio skipped when the device has an index; a tampered copy refuses with nothing staged; an interrupted install reruns; newer request ignored, in MediaRestoreTests.swift (FILE-006-S4)

## Phase 5: User Story 4 - App (P2)

- [ ] FILE-006-T10 [US4] `FolderBackupCoordinator` (backup and restore off the main thread under the folder's security scope; summary text; pending state; result once; mutual exclusion with FILE-005 restore and FILE-011 erase) and the launch hook in LibraryBackupCoordinator.swift, in Apps/projectM-iOS/Coordinators/FolderBackupCoordinator.swift (contract B6; FILE-006-R1, R8, R9)
- [ ] FILE-006-T11 [US4] Backup section rows, folder picker and footer in Apps/projectM-iOS/Views/LibraryBackupSection.swift; DEBUG `-uitestBackupFolder`, `-uitestMediaRestoreFrom`, `-uitestMediaSeed` (FILE-006-R1, R9)
- [ ] FILE-006-T12 [US4] App unit tests: summary text; backup then stage then launch install into a temp root; refused while a restore or erase is pending, in Apps/projectM-iOS/Tests/FolderBackupAppTests.swift
- [ ] FILE-006-T13 [US4] UI test: seeded media, two folder backups in one launch; the second reports "0 copied" and the assets unchanged, in Apps/projectM-iOS/UITests/FolderBackupUITests.swift (FILE-006-S5)

## Phase 6: Polish

- [ ] FILE-006-T14 ADR (folder backup format, change detection, prune and restore rules); privacy policy line; spec status; repo checks (compliance, docs, motion, permission catalog, status events, scripts, privacy manifest, network symbols); type-check budget (FILE-006-R10, R11)

## Dependencies

T01-T03 → T04, T05 → T06, T07 → T08 → T09 → T10 → T11 → T12, T13 → T14.
