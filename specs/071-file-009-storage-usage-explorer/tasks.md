# Tasks: FILE-009 Storage Usage Explorer

**Input**: `specs/071-file-009-storage-usage-explorer/` (spec, plan, research, data-model, contract,
quickstart)

Budgets (owner rule 7): each unit test about 1-2 s (≤ 10 s), each suite < 1 minute, the UI test < 30 s.
Simulator results are never device evidence.

## Phase 1: Foundational — LocalPortability (blocks every story)

- [ ] FILE-009-T01 `StorageCategory` (nine cases in display order, titles), `StorageEntry` (kind file / directory / symbolicLink / other; contentBytes, spaceUsed), `StorageDirectoryReading`, `StorageWalkLimits` ("maxDepth (32), maxEntriesPerWalk (100,000)"), `StorageUsage`, `StorageRequest`, `StorageReport` and `StorageUsageCalculator.measure` (iterative walk, links never entered, roots outside the container or that are links skipped, other-app-data walk excludes category roots, `Task.isCancelled` every 256 entries) in `Packages/LocalPortability/Sources/LocalPortability/StorageUsage.swift` (FILE-009-R3, R4, R5, R9; contract)
- [ ] FILE-009-T02 `FileManagerStorageReader` (only `isRegularFileKey`, `isDirectoryKey`, `isSymbolicLinkKey`, `fileSizeKey`, `totalFileAllocatedSizeKey`, `fileAllocatedSizeKey`; space used falls back to content bytes when not reported) in the same file (FILE-009-R8)

## Phase 2: US2 — totals agree with the files on disk (P1)

**Independent test**: a fixture tree with known sizes measured on the real file system and with an injected reader.

- [ ] FILE-009-T03 [P] [US2] `Packages/LocalPortability/Tests/LocalPortabilityTests/StorageUsageTests.swift`: real fixture tree (≥ 200 small files, nested folders, a sparse file, an empty folder, a link to an outside folder holding a large file) → content bytes exact, space used ≤ content + 4096 per file, sparse file uses less than its length where the platform reports allocation, the outside folder never listed (FILE-009-S1, S3)
- [ ] FILE-009-T04 [P] [US2] Same file: injected-reader tests for the depth limit, the entry limit (stops exactly at the limit, incomplete), an unreadable folder (incomplete), roots outside the container or that are links (skipped), category roots excluded from other app data, total = Σ categories, cancellation throws (FILE-009-S2, S3)

## Phase 3: US1 — see what the app's data takes up (P1)

**Independent test**: seed fixtures, open Settings › Storage, read each value; refresh after adding a recording.

- [ ] FILE-009-T05 [US1] `Apps/projectM-iOS/Coordinators/StorageLocations.swift` (`standard()`, `make(applicationSupport:temporary:caches:container:)`, `request`) naming folders from the stores' definitions; `PhotoStore` / `VideoStore` gain a `folderName` constant; `project.yml` adds `LocalPortability` to the app target (FILE-009-R2)
- [ ] FILE-009-T06 [US1] `Apps/projectM-iOS/Tests/StorageLocationsTests.swift`: `standard()` equals the stores' default directories; one file per baseline folder in a redirected temporary container is counted in exactly its category (FILE-009-S2)
- [ ] FILE-009-T07 [US1] `Apps/projectM-iOS/Coordinators/StorageUsageModel.swift` (`@Observable`, detached utility task, cancels the previous one, generation counter) and `Apps/projectM-iOS/Views/StorageUsageView.swift` (nine rows + total with accessibility labels and values, Refresh, busy indicator, incomplete note, footer; no delete actions) and one `NavigationLink("Storage")` in `Apps/projectM-iOS/Views/SettingsView.swift` (FILE-009-R1, R5, R6, R7)
- [ ] FILE-009-T08 [US1] `Apps/projectM-iOS/Debug/UITestStorageFixture.swift`: `-uitestStorageFixture` seeds `<tmp>/StorageFixture/container` with the research R7 sizes and enables "Add Test Recording" (2,000,000 B into Recordings) (FILE-009-R10)
- [ ] FILE-009-T09 [US1] `Apps/projectM-iOS/UITests/StorageUsageUITests.swift`: open Settings › Storage with `app.reveal`, the seeded values appear (Recordings "1 MB"), Add Test Recording + Refresh → Recordings "3 MB", total grows, Photos unchanged (FILE-009-S4)

## Phase 4: US3 — measuring never gets in the way (P2)

- [ ] FILE-009-T10 [US3] `Apps/projectM-iOS/Tests/StorageLocationsTests.swift` (model section): the model drops a cancelled measurement's result and shows only the newest (FILE-009-R5)

## Phase 5: Polish

- [ ] FILE-009-T11 Gates: `check_compliance.py`, `validate_docs.py`, `swift test` for LocalPortability on the host and the Linux shape, `xcodebuild test` (projectM-iOSTests, StorageUsageUITests, SettingsUITests) on an iOS 27.2 simulator, `check_privacy_manifest.py` on the Debug app, PosterBoard report count unchanged
- [ ] FILE-009-T12 {device} D1 with real media: import a photo, a video and an audio track, record a clip, open Settings › Storage; values are plausible against iPhone Storage's "Documents & Data" for the app (quickstart step 5)

## Dependencies

T01 → T02 → (T03, T04) and T05 → T06 → T07 → T08 → T09 → T10 → T11; T12 after T11 (device, owner).
T03 and T04 can run in parallel with T05-T06.

## Implementation strategy

MVP = Phase 1 + 2 (the acceptance). Then the screen (Phase 3), cancellation (Phase 4), gates.
