# Tasks: FILE-008 User Asset Deduplication

**Input**: Design documents from `specs/117-file-008-user-asset-deduplication/`

**Tests**: Requested by the roadmap row (schema and fixture tests plus the simulator). Budgets
(owner rule 7): unit tests about 1-2 s (at most 10 s), package suite under 1 minute, UI test under
30 s.

## Phase 1: Foundational (package code)

- [ ] FILE-008-T01 Streaming content hash (`MediaContentHash.sha256(fileAt:)`, CryptoKit on Apple, `PortableSHA256.Hasher` elsewhere, 1 MiB chunks) in Packages/LocalPortability/Sources/LocalPortability/MediaContentHash.swift (FILE-008-R2; research D2)
- [ ] FILE-008-T02 `ContentAddressedMediaFolder` (registry read/write, intern, resolve, release, releaseOthersSharing, trim, prepare, reconcile, usage, logicalFiles, per-folder lock, fault hook) in Packages/LocalPortability/Sources/LocalPortability/ContentAddressedMediaFolder.swift (FILE-008-R1-R4, R7, R8; contract M1-M11)
- [ ] FILE-008-T03 Package tests: identical interns → 1 payload and 2 references; release one keeps, both delete; legacy migration with a fault at every step then a rerun; prepare removes temp and migrated legacy names; damaged or hostile registry; usage numbers; two concurrent interns of one content give one payload; hash agrees with `PortableSHA256` in Packages/LocalPortability/Tests/LocalPortabilityTests/ContentAddressedMediaFolderTests.swift (FILE-008-S1-S3)
- [ ] FILE-008-T04 `MovieHeaderTimes.zero(fileAt:)` with a pure offset finder in Packages/Compositor/Sources/VideoLayer/MovieHeaderTimes.swift; call it from VideoSanitizer.swift after the export (FILE-008-R6; research D4)
- [ ] FILE-008-T05 MovieHeaderTimes package tests (synthetic version 0 and 1 atoms, truncated and hostile input) in Packages/Compositor/Tests (FILE-008-R6)

## Phase 2: User Story 1 - Re-importing keeps one copy (P1)

- [ ] FILE-008-T06 [US1] PhotoStore and VideoStore through the folder (stage to `.incoming-`, intern, adopt, makeCurrent keeps same-payload references, remove, discard, knownIDs, existingFile via resolve; identifiers stay canonical UUIDs, FILE-008-R3) in Apps/projectM-iOS/Coordinators/PhotoStore.swift and VideoStore.swift (contract S1-S6)
- [ ] FILE-008-T07 [US1] Availability counts every resolving reference (AppCoordinator, SceneArchiveService) and an alias of the current video restores its loop (VideoCoordinator) (FILE-008-R5)
- [ ] FILE-008-T08 [US1] Archive import of an already stored photo or video adds no payload and does not report it replaced in SceneArchiveService.swift (FILE-008-R10)
- [ ] FILE-008-T09 [US1] App tests: two identical photo imports → 1 payload file, 2 references, both resolve, a cue naming the first is not missing; the same with the fixture video; release one / both; a different photo releases the old content; Remove leaves no payload; archive import of present media adds 0 payloads in Apps/projectM-iOS/Tests/MediaDeduplicationTests.swift (FILE-008-S1, S2, S5); update existing PhotoStore/VideoStore/archive tests for payload names

## Phase 3: User Story 3 - Migration (P1)

- [ ] FILE-008-T10 [US3] Launch reconcile in AppCoordinator.init after the FILE-005 restore recovery: synchronous `prepare`, then `reconcile` on a utility task (FILE-008-R7, R8; research D5)
- [ ] FILE-008-T11 [US3] App test: legacy `<UUID>.png` and `<UUID>.mov` with the current keys set migrate; old identifiers resolve before, during (fault at each step) and after; next prepare removes the legacy names in MediaDeduplicationTests.swift (FILE-008-S3)

## Phase 4: User Story 4 - Backup, archives and storage (P2)

- [ ] FILE-008-T12 [US4] LibraryContents reads photos through `logicalFiles()` in Packages/LibraryBackup/Sources/LibraryBackup/LibraryContents.swift; package test: a deduplicated folder backs up the same entries as the plain layout and restores exactly (FILE-008-R9, S4)
- [ ] FILE-008-T13 [US4] App backup round trip over a deduplicated Photos folder in Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift (FILE-008-S4)
- [ ] FILE-008-T14 [US4] Storage savings: model computes logical − physical for Photos and Videos; the view shows the note; model test; the storage UI fixture gets a shared payload and StorageUsageUITests asserts the note (FILE-008-R11, S6)

## Phase 5: Polish

- [ ] FILE-008-T15 ADR (next free number) for the content-addressed media store and its migration; spec status; docs checks (compliance, validate_docs, motion, permission catalog, status events, script tests, privacy manifest on the Debug app) (FILE-008-R12)
- [ ] FILE-008-T16 Run the app unit tests, the five UI suites and the touched package suites on an own iOS 27.2 simulator and the host; record counts and durations; PosterBoard count before and after

## Dependencies

T01 → T02 → T03; T04 → T05; T02 → T06 → T07, T08 → T09; T06 → T10 → T11; T02 → T12 → T13; T02 → T14; all → T15, T16.
