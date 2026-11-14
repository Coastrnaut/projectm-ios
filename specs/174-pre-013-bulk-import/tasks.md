# Tasks: PRE-013 Bulk Preset Import

**Input**: `specs/174-pre-013-bulk-import/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the roadmap row's acceptance and the brief (100-file fixture from a folder and a
zip, cancel, zip slip, one UI test under 30 s).

Format: `- [ ] PRE-013-Tnn [P?] [Story?] Description (file)`.

## Phase 1: Setup

- [X] PRE-013-T01 Create the simulator "PRE13 iPhone 17" (iOS 27.2), count PosterBoard reports, `xcodegen generate` in the worktree. — Verified 2026-11-14: simulator "PRE13 iPhone 17" (iOS 27.2) created; 25 PosterBoard reports before; `xcodegen generate` OK; preset submodules initialized

## Phase 2: Foundational

- [X] PRE-013-T02 `LooseZipReader` (contract C1: per-entry verdicts, "unsafe path checked first", stored and deflate reads with "exactly the declared size and CRC-32", output never more than `limit + 1` bytes); the byte reader in `StoredZip.swift` becomes internal (`Packages/LocalPortability/Sources/LocalPortability/LooseZipReader.swift`, `StoredZip.swift`). — Verified 2026-11-14: `swift test --package-path Packages/LocalPortability` 127/127 (LooseZipReaderTests 7/7, StoredZipTests unchanged)
- [X] PRE-013-T03 [P] `LooseZipReaderTests`: stored and (Apple platforms) deflate entries read back; `../x.milk`, `/x.milk`, `a\\b.milk` unsafe; Unix symlink entry; encrypted flag; method 12; CRC damage throws; directories and `__MACOSX` entries; not a ZIP is refused (`Packages/LocalPortability/Tests/LocalPortabilityTests/LooseZipReaderTests.swift`). — Verified 2026-11-14: LooseZipReaderTests 7/7 on the macOS host (deflate case runs where Compression exists)
- [X] PRE-013-T04 Model and words (data model: limits "2,000 files", "64 MiB", "8 levels", "batches of 50"; kinds, items, counts, report, progress; contract C2 texts) (`Packages/PresetLibrary/Sources/PresetLibrary/BulkImport/BulkImportModel.swift`). — Verified 2026-11-14: BulkImportAcceptanceTests testSummaryWords and every summary assertion; `swift test --package-path Packages/PresetLibrary` 297 tests, 0 failures (3 skipped, pre-existing)
- [X] PRE-013-T05 `UserPresetLibrary` access levels; `bulkImportBaseline()` and `commitBulk(_:)` (re-check duplicates and the 1,000 cap, build records as `importFile` does, save through `commitImport`) (`Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/UserPresetLibrary.swift`, `BulkImport/UserPresetLibrary+BulkImport.swift`). — Verified 2026-11-14: BulkImportAcceptanceTests testAFailingBatchTurnsItsFilesIntoFailures, testLibraryFullFailsTheRest (cap via `BulkImportLimits.maxLibraryPresets`); `swift test --package-path Packages/PresetLibrary` 297 tests, 0 failures (3 skipped, pre-existing)

## Phase 3: User Story 1 — import a folder (P1) MVP

Independent test: the 100-file fixture folder reports added 70, duplicates 15, invalid 8, too large 4, unsupported 3, failed 0; the store holds the 5 seeded and the 70 new presets.

- [X] PRE-013-T06 [US1] Folder listing (contract C1: hidden entries, symlinks not followed, depth 8, stop at 2,001 files, 64 MiB candidate bytes) (`Packages/PresetLibrary/Sources/PresetLibrary/BulkImport/BulkImportSource.swift`). — Verified 2026-11-14: BulkImportAcceptanceTests testFolderOf100FilesReportsExactCounts (hidden .DS_Store counted), testLinksAndDeepFoldersAreNotFollowed, testOverTheBoundsNothingIsImported
- [X] PRE-013-T07 [US1] `BulkPresetImporter.run` (contract C3 order, batches of 50, progress after each file) (`Packages/PresetLibrary/Sources/PresetLibrary/BulkImport/BulkPresetImporter.swift`). — Verified 2026-11-14: BulkImportAcceptanceTests (11/11, 1.3 s in total on the macOS host)
- [X] PRE-013-T08 [US1] Fixture generator (100 files in the temporary folder, nothing committed) and the folder acceptance test (S1) with per-file list checks (`Packages/PresetLibrary/Tests/PresetLibraryTests/BulkImportFixture.swift`, `BulkImportAcceptanceTests.swift`). — Verified 2026-11-14: BulkImportAcceptanceTests testFolderOf100FilesReportsExactCounts: added 70, duplicates 15, invalid 8, too large 4, unsupported 3, failed 0; store holds the 5 seeded and exactly the 70 new presets (0.31 s)
- [ ] PRE-013-T09 [US1] App: `BulkPresetImportCoordinator` (detached run, progress, Cancel, report, library-lane announcements at start, quarters and end, then trials and refresh) and the busy rules in `UserPresetsCoordinator` (`Apps/projectM-iOS/Coordinators/BulkPresetImportCoordinator.swift`, `UserPresetsCoordinator.swift`).
- [ ] PRE-013-T10 [US1] Views: the "Import Folder or Archive…" row with its `fileImporter` (`.folder`, `.zip`), progress row with Cancel, summary sheet with the per-file list and filter; wired into My Presets (`Apps/projectM-iOS/Views/BulkPresetImportViews.swift`, `UserPresetsView.swift`).

## Phase 4: User Story 2 — import a `.zip` (P1)

- [X] PRE-013-T11 [US2] Archive listing through `LooseZipReader` (contract C1, 64 MiB archive) in `BulkImportSource.swift`. — Verified 2026-11-14: BulkImportAcceptanceTests testStoredZipReportsTheSameCounts, testDeflatedZipReportsTheSameCounts (`__MACOSX` entry counted as hidden)
- [X] PRE-013-T12 [US2] Acceptance: the fixture as a stored zip (all platforms) and as a deflate zip (Apple platforms) gives the S1 counts; zip slip entries (`../`, absolute) are unsupported and nothing is written outside the store directory (S4) (`BulkImportAcceptanceTests.swift`). — Verified 2026-11-14: BulkImportAcceptanceTests testStoredZipReportsTheSameCounts, testDeflatedZipReportsTheSameCounts, testZipSlipEntriesAreSkippedAndNothingIsWrittenOutsideTheStore

## Phase 5: User Story 3 — cancel (P2)

- [X] PRE-013-T13 [US3] Tests: cancel after 30 files → 30 handled, counts add up, every added preset stored and no other, 70 not handled; importing again reports the first run's presets as duplicates; bounds refusals (2,001 files, 64 MiB) store nothing; a failing batch turns its drafts into failed (`BulkImportAcceptanceTests.swift`). — Verified 2026-11-14: BulkImportAcceptanceTests testCancelAfter30FilesKeepsExactlyWhatWasAdded (30 handled, 70 not handled, store gains exactly the added; re-import adds the rest), testCancelBeforeTheFirstFileAddsNothing, testOverTheBoundsNothingIsImported, testAFailingBatchTurnsItsFilesIntoFailures
- [ ] PRE-013-T14 [US3] App tests: announcements (start, quarters once each, summary; cancelled summary) on the library lane, single import refused while a bulk import runs, no file written outside the user preset store by a run (R14) (`Apps/projectM-iOS/Tests/BulkPresetImportCoordinatorTests.swift`).

## Phase 6: Polish

- [ ] PRE-013-T15 [P] ImportFuzz: mutated archives through `LooseZipReader` never trap and every entry gets a verdict (`Packages/ImportFuzz/Tests/ImportFuzzTests/BulkArchiveFuzzTests.swift`).
- [ ] PRE-013-T16 UI test under 30 s (S5): a small fixture folder written by the test, `-uitestBulkImportFolder`, open My Presets, read `bulkImportSummary` (`Apps/projectM-iOS/UITests/BulkPresetImportUITests.swift`, DEBUG flag in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`).
- [ ] PRE-013-T17 `scripts/check_status_events.py` covers the new app files; repo checks; no automatic tagging in the new code (R12, review); type-check budget; Linux-guard review; privacy manifest and network symbol checks on the Debug app.
- [ ] PRE-013-T18 Spec status, delete the simulator and derived data, PosterBoard count.

## Dependencies

T01 → T02 → T03; T04 → T05 → T06 → T07 → T08 → (T09 → T10); T02 → T11 → T12; T07 → T13; T09 → T14;
T02 → T15; T10 → T16 → T17 → T18. T03 and T15 can run in parallel with the PresetLibrary work.

## Implementation strategy

MVP is US1 (folder import with exact counts). US2 adds the archive source on the same pipeline; US3
proves cancel and bounds. Every task is verified by the named test before it is ticked.
