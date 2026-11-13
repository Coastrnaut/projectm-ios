# Tasks: FILE-010 Safe Cache Cleanup

**Input**: `specs/072-file-010-safe-cache-cleanup/` (spec, plan, research, data-model, contract,
quickstart)

Budgets (owner rule 7): each unit test about 1-2 s (≤ 10 s), each suite < 1 minute, the UI test < 30 s.
Simulator results are never device evidence.

## Phase 1: Foundational — LocalPortability (blocks every story)

- [X] FILE-010-T01 `StorageCategory.cleanable`, `CacheCleanupRequest`, `CacheCleanupItem`, `CacheCleanupRefusal`, `CacheCleanupPlan`, `CacheCleanupResult`, `CacheCleanupFileSystem` (FILE-009 reader + `removeItem(atPath:)`), `FileManagerCacheCleanupFileSystem` and `CacheCleaner.plan(_:)` / `execute(_:inUse:)` in `Packages/LocalPortability/Sources/LocalPortability/CacheCleanup.swift` (FILE-010-R3, R4, R5, R7, R8, R9; contract C1-C3) — Verified 2026-11-13: `swift test --package-path Packages/LocalPortability` (93 tests pass on the Mac host, 3.4 s), CacheCleanupTests

## Phase 2: US2 — user data is never touched (P1)

**Independent test**: plan and clear an injected tree and a real temporary tree; then the app's fixture container with its own loaders.

- [X] FILE-010-T02 [P] [US2] `Packages/LocalPortability/Tests/LocalPortabilityTests/CacheCleanupTests.swift`, injected file system (Linux shape): each refusal (not cleanable, link root, container itself, outside, overlaps protected both ways, duplicate); hostile names ignored; in-use file kept and its folder entered; execute re-checks (vanished, parent became a link, now in use, removal error continues) (FILE-010-S3) — Verified 2026-11-13: CacheCleanupTests (10 injected-file-system tests: every refusal, a root resolving into Photos, hostile names, in-use file and whole folder, execute re-checks incl. a folder that became a link and an injected removal error, links removed alone, walk limits; 0.007 s on the Mac host; Linux lane runs in CI)
- [X] FILE-010-T03 [P] [US2] Same file, real file system: a link in a cache folder (and one nested in a cache sub-folder) to a user file and a user folder → links removed, targets byte-identical; sizes and `bytesToFree` match the bytes written (FILE-010-S2) — Verified 2026-11-13: CacheCleanupTests.testLinksToUserDataAreRemovedAndTheirTargetsUntouched (real file system: links to the photo, the Videos folder and Application Support removed, targets byte-identical, caches content 3,000 B and shares 500 B as written; 0.005 s)
- [X] FILE-010-T04 [US2] `Apps/projectM-iOS/Coordinators/StorageLocations.swift`: `showFolderName`, `preferencesFolder`, `protectedRoots`, `cleanupRequest(inUse:)`; `CacheCleanupAcceptanceTests.testProtectedRootsAreTheUserDataFoldersAndTheRequestHoldsOnlyCaches` checks `Show` agrees with `ShowStore.defaultDirectory()` (FILE-010-R3) — Verified 2026-11-13: CacheCleanupAcceptanceTests.testProtectedRootsAreTheUserDataFoldersAndTheRequestHoldsOnlyCaches (FILE10 iPhone 17, iOS 27.2 simulator)
- [X] FILE-010-T05 [US2] `Apps/projectM-iOS/Tests/CacheCleanupAcceptanceTests.swift`: the fixture container (photo, video, current + backup scene via `SceneAutosaveStore`, a show with two scene snapshots via `ShowStore`, user presets, a collection, imported audio, preferences; caches in all five folders, a leftover and an offered recording, a link to the photo) → plan + execute → every user file byte-identical, main and backup scenes load, both show scenes load, caches gone, offered recording kept (FILE-010-S1, S2) — Verified 2026-11-13: CacheCleanupAcceptanceTests.testCleanupRemovesCacheOnlyAndEverySavedSceneStillLoads (11 user files byte-identical, 7 cache items removed incl. 2 links, offered recording kept, SCN-002 main and backup load, both SHOW-001 scenes decode; 0.045 s on the iOS 27.2 simulator)

## Phase 3: US1 — free the space caches take (P1)

**Independent test**: Settings › Storage › Clear Caches… › Clear on the fixture.

- [X] FILE-010-T06 [US1] `Apps/projectM-iOS/Coordinators/StorageUsageModel.swift`: `prepareCleanup()`, `confirmCleanup()`, `dismissCleanup()`, `pendingPlan`, `isClearing`, `lastCleanup`, an in-use provider; detached utility tasks; refresh after clearing; model tests in `CacheCleanupAcceptanceTests`: Cancel removes nothing, an empty plan gives the nothing-to-clear state, leaving the screen does not stop a clear (FILE-010-R2, R6) — Verified 2026-11-13: CacheCleanupAcceptanceTests.testTheModelConfirmsClearsAndReportsNothingLeft (Cancel removes nothing, Clear survives `cancel()`, refresh shows Caches 0, then "nothing to clear" with files in use; 0.034 s)
- [X] FILE-010-T07 [US1] `Apps/projectM-iOS/Views/StorageUsageView.swift`: Clear Caches… section, the alerts and result notes (contract C4); `UITestStorageFixture` seeds the two export folders, a show and a preferences file (FILE-010-R1, R2, R9) — Verified 2026-11-13: CacheCleanupUITests (alert text, cleared note) and StorageUsageUITests still passes with the extended fixture
- [X] FILE-010-T08 [US1] `Apps/projectM-iOS/UITests/CacheCleanupUITests.swift`: fixture → Clear Caches… → alert text → Clear → Recordings, Shares and exports, Caches "Zero KB"; Photos, Videos, Scenes, Presets, Imported audio unchanged (FILE-010-S4) — Verified 2026-11-13: CacheCleanupUITests.testClearCachesEmptiesTheCacheCategoriesAndKeepsUserData passed (19.6 s; an earlier run with an extra scroll took 31.2 s)

## Phase 4: US3 — files in use are kept (P2)

- [X] FILE-010-T09 [US3] `VideoRecordingCoordinator.filesInUse`, `UserPresetsCoordinator.filesInUse`, `Apps/projectM-iOS/Coordinators/AppCoordinator+CacheCleanup.swift` (`cacheFilesInUse()`), the provider passed through `SettingsView` and `VisualizerView`; model test: an in-use path from the provider is kept and the plan is re-checked at clear time (FILE-010-R5) — Verified 2026-11-13: app builds with the provider wired through SettingsView and VisualizerView; CacheCleanupAcceptanceTests.testIdleCoordinatorsHoldNoFilesInUse and the model test (injected in-use path kept at plan and at clear time). The live recording/share/export in-use states are covered by code reading, not by a test of a running recording

## Phase 5: Polish

- [X] FILE-010-T10 Gates: `check_compliance.py`, `validate_docs.py`, `swift test` for LocalPortability on the host, `xcodebuild test` (projectM-iOSTests, CacheCleanupUITests, StorageUsageUITests, SettingsUITests) on an own iOS 27.2 simulator, `check_privacy_manifest.py` on the Debug app, PosterBoard report count unchanged (FILE-010-R7, S5) — Verified 2026-11-13: check_compliance OK; validate_docs OK; LocalPortability 93 tests on the Mac host (3.4 s; Linux lane runs in CI after push, not run locally: no Linux host); projectM-iOSTests 328 pass (15.3 s) and projectM-iOSUITests CacheCleanupUITests (17.4 s) + StorageUsageUITests + SettingsUITests (4) = 6 pass (140.7 s) on the FILE10 iPhone 17 iOS 27.2 simulator (SettingsUITests.testLicensesScreen took 30.6 s, a pre-existing test); check_privacy_manifest OK on the Debug app with the manifest unchanged; PosterBoard reports 32 before and after
- [ ] FILE-010-T11 {device} D1: after preset switches and a shared recording, Clear Caches frees the Caches size; the app plays and the current scene and show load after relaunch (quickstart, Device)

## Dependencies

T01 → T02, T03 (parallel) → T04 → T05; T04 → T06 → T07 → T08; T06 → T09; everything → T10. T11 needs a person and D1.
