# Tasks: FILE-008 User Asset Deduplication

**Input**: Design documents from `specs/117-file-008-user-asset-deduplication/`

**Tests**: Requested by the roadmap row (schema and fixture tests plus the simulator). Budgets
(owner rule 7): unit tests about 1-2 s (at most 10 s), package suite under 1 minute, UI test under
30 s.

## Phase 1: Foundational (package code)

- [X] FILE-008-T01 Streaming content hash (`MediaContentHash.sha256(fileAt:)`, CryptoKit on Apple, `PortableSHA256.Hasher` elsewhere, 1 MiB chunks) in Packages/LocalPortability/Sources/LocalPortability/MediaContentHash.swift (FILE-008-R2; research D2) — Verified 2026-11-14: `swift test --package-path Packages/LocalPortability --filter ContentAddressedMediaFolderTests` (testStreamingHashMatchesTheOneShotHash) passes with CryptoKit and with `-Xswiftc -DLOCALPORTABILITY_NO_CRYPTOKIT` (the Linux path)
- [X] FILE-008-T02 `ContentAddressedMediaFolder` (registry read/write, intern, resolve, release, releaseOthersSharing, trim, prepare, reconcile, usage, logicalFiles, per-folder lock, fault hook) in Packages/LocalPortability/Sources/LocalPortability/ContentAddressedMediaFolder.swift (FILE-008-R1-R4, R7, R8; contract M1-M11) — Verified 2026-11-14: ContentAddressedMediaFolderTests 15/15 on the host (0.33 s; 0.83 s on the portable-hash path); LocalPortability suite 108/108
- [X] FILE-008-T03 Package tests: identical interns → 1 payload and 2 references; release one keeps, both delete; legacy migration with a fault at every step then a rerun; prepare removes temp and migrated legacy names; damaged or hostile registry; usage numbers; two concurrent interns of one content give one payload; hash agrees with `PortableSHA256` in Packages/LocalPortability/Tests/LocalPortabilityTests/ContentAddressedMediaFolderTests.swift (FILE-008-S1-S3) — Verified 2026-11-14: ContentAddressedMediaFolderTests 15/15: 1 payload + 2 references, release one/both, fault at every migration step (more than 3 steps injected) and at each intern step, concurrent interns, hostile registry, usage
- [X] FILE-008-T04 `MovieHeaderTimes.zero(fileAt:)` with a pure offset finder in Packages/Compositor/Sources/VideoLayer/MovieHeaderTimes.swift; call it from VideoSanitizer.swift after the export (FILE-008-R6; research D4) — Verified 2026-11-14: MovieHeaderTimesTests 3/3; a spike exporting the fixture movie twice 2 s apart gave 6 differing bytes before and byte-identical files after `MovieHeaderTimes.zero`; Compositor suite 382 tests, 0 failures (6 skipped)
- [X] FILE-008-T05 MovieHeaderTimes package tests (synthetic version 0 and 1 atoms, truncated and hostile input) in Packages/Compositor/Tests (FILE-008-R6) — Verified 2026-11-14: MovieHeaderTimesTests 3/3 (version 0/1 fields, in-place zeroing touches only time bytes, hostile sizes write nothing)

## Phase 2: User Story 1 - Re-importing keeps one copy (P1)

- [X] FILE-008-T06 [US1] PhotoStore and VideoStore through the folder (stage to `.incoming-`, intern, adopt, makeCurrent keeps same-payload references, remove, discard, knownIDs, existingFile via resolve; identifiers stay canonical UUIDs, FILE-008-R3) in Apps/projectM-iOS/Coordinators/PhotoStore.swift and VideoStore.swift (contract S1-S6) — Verified 2026-11-14: projectM-iOSTests 528/528 on an own iOS 27.2 simulator, including the updated PhotoStoreTests 7/7 and VideoStoreTests 8/8 (payload names, registry excluded from copy counts)
- [X] FILE-008-T07 [US1] Availability counts every resolving reference (AppCoordinator, SceneArchiveService) and an alias of the current video restores its loop (VideoCoordinator) (FILE-008-R5) — Verified 2026-11-14: MediaDeduplicationTests testTwoIdenticalPhotoImportsCreateOnePayloadAndTwoReferences (availability) and testACueNamingAnOlderReferenceOfTheCurrentVideoRestoresItsLoop pass
- [X] FILE-008-T08 [US1] Archive import of an already stored photo or video adds no payload and does not report it replaced in SceneArchiveService.swift (FILE-008-R10) — Verified 2026-11-14: SceneArchiveServiceTests testImportingAnArchiveWhoseMediaAreAlreadyStoredAddsNoCopy (0 extra payloads, not replaced) and testASuccessfulImportReplacesTheStoredPhotoAndVideo (different media) pass
- [X] FILE-008-T09 [US1] App tests: two identical photo imports → 1 payload file, 2 references, both resolve, a cue naming the first is not missing; the same with the fixture video; release one / both; a different photo releases the old content; Remove leaves no payload; archive import of present media adds 0 payloads in Apps/projectM-iOS/Tests/MediaDeduplicationTests.swift (FILE-008-S1, S2, S5); update existing PhotoStore/VideoStore/archive tests for payload names — Verified 2026-11-14: MediaDeduplicationTests 8/8 (photo and fixture video: 1 payload file, 2 references; release; Remove; different photo); SceneArchiveServiceTests 6/6

## Phase 3: User Story 3 - Migration (P1)

- [X] FILE-008-T10 [US3] Launch reconcile in AppCoordinator.init after the FILE-005 restore recovery: synchronous `prepare`, then `reconcile` on a utility task (FILE-008-R7, R8; research D5) — Verified 2026-11-14: AppCoordinator+MediaStore.swift called after `finishPendingRestore`; app builds; LibraryBackupUITests, PhotoLayerUITests and VideoLayerUITests pass across relaunches
- [X] FILE-008-T11 [US3] App test: legacy `<UUID>.png` and `<UUID>.mov` with the current keys set migrate; old identifiers resolve before, during (fault at each step) and after; next prepare removes the legacy names in MediaDeduplicationTests.swift (FILE-008-S3) — Verified 2026-11-14: MediaDeduplicationTests testLegacyCopiesMigrateAndResolveBeforeDuringAndAfter passes (faults at each step, then prepare, reconcile, prepare)

## Phase 4: User Story 4 - Backup, archives and storage (P2)

- [X] FILE-008-T12 [US4] LibraryContents reads photos through `logicalFiles()` in Packages/LibraryBackup/Sources/LibraryBackup/LibraryContents.swift; package test: a deduplicated folder backs up the same entries as the plain layout and restores exactly (FILE-008-R9, S4) — Verified 2026-11-14: LibraryBackup suite 31/31 including LibraryBackupDedupTests (byte-identical backups of the plain and deduplicated layouts; exact restore; reconcile after restore); ImportFuzz LibraryBackup fuzz 300 inputs, 0 violations
- [X] FILE-008-T13 [US4] App backup round trip over a deduplicated Photos folder in Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift (FILE-008-S4) — Verified 2026-11-14: LibraryBackupAppTests testADeduplicatedPhotoLibraryBacksUpAndRestoresExactly passes
- [X] FILE-008-T14 [US4] Storage savings: model computes logical − physical for Photos and Videos; the view shows the note; model test; the storage UI fixture gets a shared payload and StorageUsageUITests asserts the note (FILE-008-R11, S6) — Verified 2026-11-14: MediaDeduplicationTests testTheStorageScreenCountsTheSharedPayloadOnceAndReportsTheSaving and StorageUsageUITests pass; CacheCleanupUITests still passes

## Phase 5: Polish

- [X] FILE-008-T15 ADR (next free number) for the content-addressed media store and its migration; spec status; docs checks (compliance, validate_docs, motion, permission catalog, status events, script tests, privacy manifest on the Debug app) (FILE-008-R12) — Verified 2026-11-14: ADR-0043 written (0043 was the next free number on every branch at commit time); check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts OK; check_privacy_manifest OK on the Debug simulator app
- [X] FILE-008-T16 Run the app unit tests, the five UI suites and the touched package suites on an own iOS 27.2 simulator and the host; record counts and durations; PosterBoard count before and after — Verified 2026-11-14: see the spec's Status line for the commands, counts and durations; PosterBoard reports 25 before and 25 after

## Dependencies

T01 → T02 → T03; T04 → T05; T02 → T06 → T07, T08 → T09; T06 → T10 → T11; T02 → T12 → T13; T02 → T14; all → T15, T16.
