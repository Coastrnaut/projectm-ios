# Tasks: REC-010 Recording library

**Input**: `specs/198-rec-010-recording-library/` (spec, plan, research, data-model, contracts/recording-library.md, quickstart)
**Tests**: requested by the roadmap acceptance (delete after confirmation updates the list immediately) and the brief (seeded acceptance, thumbnails, Incomplete, order, erase category, a UI test under 30 s).

## Phase 1: Setup

No setup: no new package, setting, key or dependency.

## Phase 2: Foundational (packages)

- [X] REC-010-T01 [P] Add `StorageCategory.savedRecordings` ("Saved recordings", after `.recordings`, not cleanable) and retitle `.recordings` "Unsaved recordings" in Packages/LocalPortability/Sources/LocalPortability/StorageUsage.swift; package test that `savedRecordings` is not cleanable and its root is protected by the cleanup plan in Packages/LocalPortability/Tests/LocalPortabilityTests/CacheCleanupTests.swift (contract C7; REC-010-R7, S5) — Verified 2026-11-14: swift test --package-path Packages/LocalPortability, 128/128 (5.7 s), incl. testSavedRecordingsAreNeverCleanable and the new title order
- [X] REC-010-T02 [P] Add `LibraryEraseCategory.recordings` ("Saved recordings", before `.settings`, folder `LibraryErasePolicy.recordingLibraryFolderName = "RecordingLibrary"`, no keys) and its inventory count (non-hidden files) in Packages/LibraryBackup/Sources/LibraryBackup/LibraryErasePolicy.swift and LibraryEraseInventory.swift; seed one file in Packages/LibraryBackup/Tests/LibraryBackupTests/EraseFixtures.swift and assert count 1 in LibraryEraseAcceptanceTests (contract C7; REC-010-R8, S5) — Verified 2026-11-14: swift test --package-path Packages/LibraryBackup, 77/77 (25 s); every category alone and all together erase only their data, inventory counts the kept recording

## Phase 3: User Story 1 - Keep and browse recordings (P1) MVP

**Goal**: Keep moves an offered recording into the library; the Recordings screen lists files newest first with thumbnail and facts.
**Independent test**: app tests with recordings generated at test time.

- [X] REC-010-T03 [US1] `RecordingLibraryStore` (folder, `scan()` ordered by modification date then name descending, hidden files skipped, `keep(_:)` with " 2"/" 3" names, `delete(_:)`, `rename(_:to:)`, `validate(name:excluding:)` with research D7 texts "Enter a name.", "Names can't contain / or :.", "Names can't start with a dot.", "Use at most 100 characters.", "A recording with that name exists.") in Apps/projectM-iOS/Coordinators/RecordingLibraryStore.swift (contract C2, C5) — Verified 2026-11-14: RecordingLibraryAcceptanceTests testRowsAreNewestFirstThenByName, testRenameRulesKeepTheExtension, testKeepMovesTheOfferedRecordingIntoTheLibrary on the REC10 iOS 27.2 simulator
- [X] REC-010-T04 [US1] `RecordingLibraryInspector` (header facts per research D4; thumbnail at min(1 s, duration / 2), max 240 px, JPEG in `Caches/RecordingThumbnails/<name>.<bytes>.jpg` plus memory cache; `removeThumbnail(for:)`) in Apps/projectM-iOS/Coordinators/RecordingLibraryInspector.swift (contract C3) — Verified 2026-11-14: testFactsComeFromTheHeader (64×64, avc1, 2 s, 10 fps), testThumbnailIsGeneratedOnceAndServedFromTheCache (one decode; a new inspector reads the cache folder)
- [X] REC-010-T05 [US1] `RecordingLibraryModel` (@Observable: items, states loading/ready/incomplete, count, totalBytes, refresh, delete request/confirm/cancel, rename, announce hook on the library lane) in Apps/projectM-iOS/Coordinators/RecordingLibraryModel.swift (contract C4; REC-010-R2-R5, R9) — Verified 2026-11-14: testDeleteAfterConfirmationRemovesTheFileAndUpdatesTheListImmediately, testCancellingTheConfirmationKeepsTheFile, testDeletingAFileThatIsAlreadyGoneStillRemovesTheRow
- [X] REC-010-T06 [US1] Keep: `VideoRecordingCoordinator.keepOffered()` and `libraryDirectory`, `onKept` hook, Keep button on the recording panel in Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift and Apps/projectM-iOS/Views/CaptureResultPanels.swift (contract C1; REC-010-R1) — Verified 2026-11-14: testKeepMovesTheOfferedRecordingIntoTheLibrary (moved not copied, offer closed, notice and library-lane text, " 2" on collision); CaptureShareUITests and RecordingDiskGuardUITests still pass with the Keep button
- [X] REC-010-T07 [US1] `RecordingLibraryView` (summary, rows with thumbnail and facts, Incomplete rows, empty state, accessibility element and actions per row) in Apps/projectM-iOS/Views/RecordingLibraryView.swift; the Saved recordings row as the link, the kept note naming saved recordings and `.savedRecordings` root in StorageUsageView.swift and StorageLocations.swift; wiring in SettingsView.swift, VisualizerView.swift and AppCoordinator.swift (contract C8; REC-010-R2-R4, R9) — Verified 2026-11-14: RecordingLibraryUITests (Saved recordings row opens Recordings, rows and summary); StorageLocationsTests 4/4; the link became the Saved recordings row itself (contract C8) so Storage gets no extra row; build with the type-check flags: no warning in changed code
- [X] REC-010-T08 [US1] DEBUG fixture: generated H.264 recordings (AVAssetWriter, 64×64, 2 s at 10 fps) and `-uitestRecordingLibrarySeed <n>` in Apps/projectM-iOS/Debug/RecordingLibraryFixture.swift (contract C8) — Verified 2026-11-14: the seed writes 3 readable files used by the app tests and the UI test (-uitestRecordingLibrarySeed 3); one encode per run, copied (unit tests 1.0 s for 10)

## Phase 4: User Story 2 - Delete a recording (P1)

**Goal**: the roadmap acceptance.
**Independent test**: seeded acceptance test and the UI test.

- [X] REC-010-T09 [US2] Acceptance tests in Apps/projectM-iOS/Tests/RecordingLibraryAcceptanceTests.swift: seed 3, delete the middle with confirmation (file gone, 2 rows in the same update, total and the FILE-009 "Saved recordings" measurement drop by its size, thumbnail entry removed); cancel keeps it; thumbnail generated and cached; Incomplete row has Delete only; order newest first; Keep moves the offered file and names a collision "<stem> 2.mp4"; Clear Caches plan never touches the library (REC-010-S1-S5) — Verified 2026-11-14: RecordingLibraryAcceptanceTests 10/10 on REC10 (1.0 s): middle row deleted after confirmation, file gone, 2 rows with no await in between, model total and FILE-009 Saved recordings drop by its size, thumbnail entry gone; Cancel keeps 3; Incomplete has Delete only; order; Keep; Clear Caches plan never enters the library; erase plan removes RecordingLibrary
- [X] REC-010-T10 [US2] UI test in Apps/projectM-iOS/UITests/RecordingLibraryUITests.swift: launch with `-uitestRecordingLibrarySeed 3`, Settings › Storage › Recordings, Delete on one row, confirm, the summary reads 2 recordings (REC-010-S6, under 30 s) — Verified 2026-11-14: RecordingLibraryUITests 1/1 on REC10 in 11.1 s and 12.6 s

## Phase 5: User Story 3 - Play, share and rename (P2)

- [X] REC-010-T11 [US3] Play (AVKit `VideoPlayer` sheet), Share… (`ActivitySharePresenter` with the file) and Rename (alert with a text field, validation message) in Apps/projectM-iOS/Views/RecordingLibraryView.swift; rename tests (valid, each refusal, extension kept, cache key moved) in RecordingLibraryAcceptanceTests (contract C5, C6; REC-010-R6) — Verified 2026-11-14: testRenameRulesKeepTheExtension (every refusal text, extension kept, old cache entry removed); Play and Share wired in RecordingLibraryView (share uses REC-012's presenter and excluded activities); playback and the share sheet itself are not drivable here, see T13

## Phase 6: Polish

- [X] REC-010-T12 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests, privacy manifest on the Debug app, network symbols), the type-check budget, StorageLocationsTests and the touched package suites; spec status — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 OK; check_privacy_manifest OK and check_network_symbols OK on the Debug app; LocalPortability 128, LibraryBackup 77; app regression: CacheCleanupAcceptanceTests, LibraryEraseAppTests, VideoRecordingAppTests, FolderBackupAppTests, StorageUsageUITests, CacheCleanupUITests (updated for the new row and kept note), LibraryEraseUITests, CaptureShareUITests, RecordingDiskGuardUITests pass
- [ ] REC-010-T13 {device} On D1: record, Keep, open Recordings, play, share to Files, rename, delete.

## Dependencies

T01, T02 first (parallel). T03 → T04 → T05 → T06, T07, T08 → T09, T10 → T11 → T12. T13 after merge.

## Parallel Example

T01 and T02 touch different packages; T06 and T08 touch different files.

## Implementation Strategy

MVP = US1 + US2 (Keep, list, delete with confirmation). US3 adds play, share and rename on the same screen.
