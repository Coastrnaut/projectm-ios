# Tasks: PRE-002 Thumbnail Invalidation

**Input**: `specs/144-pre-002-thumbnail-invalidation/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (PRE-002-S1 to S5). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, each xcodebuild run under 10 minutes; no wall-clock
assertions (the cache's sleep is injected). No `{device}` task: nothing here needs a device.

## Phase 1: Setup

- [ ] PRE-002-T01 Run `xcodegen generate`, initialize the preset submodules if missing, link `Build` to the main checkout's `Build` if the xcframeworks are missing, create the simulator "PRE2 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run

## Phase 2: Foundational (blocks every story)

- [ ] PRE-002-T02 [P] Pure selection helpers on `PresetThumbnailIndex` in `Packages/PresetLibrary/Sources/PresetLibrary/Thumbnails/PresetThumbnailInvalidation.swift`: `staleIDs(presetID:keepingContentHash:)` ("same `presetID`, `contentHash != keepingContentHash` (all when nil)") and `unlistedIDs(_ listing: [String: String])` (entry kept only if `listing[entry.presetID] == entry.contentHash`), plus a `removeEntries(_:in:fileManager:)` that deletes the entries' files (safe names only) and returns the count
- [ ] PRE-002-T03 `PresetThumbnailCache.invalidate(presetID:keepingContentHash:) -> Int` and `retainOnly(_:) -> Int` (contract C1, C2: remove entries, files and remembered failures; save only when something was removed; cancel queued requests of stale keys with `CancellationError`; an in-flight stale render stores nothing and answers `unavailable`; all work runs inside the cache actor and never throws, R8) in `Packages/PresetLibrary/Sources/PresetLibrary/Thumbnails/PresetThumbnailCache.swift`; document the renderer version bump rule (C4) on `PresetThumbnailSpec.rendererVersion` in `PresetThumbnailSpec.swift`

## Phase 3: User Story 1 - An edited preset shows its new picture (P1) — MVP and acceptance

**Independent test**: counting fake renderer; cache A, B, C; change B; second pass renders only B, B's old file is gone, A and C keep file, ID and modification date.

- [ ] PRE-002-T04 [US1] Package tests in `Packages/PresetLibrary/Tests/PresetLibraryTests/PresetThumbnailInvalidationTests.swift`: acceptance (S1), rename keeps the thumbnail (S4), a queued stale request is cancelled and an in-flight stale render is not stored (R5), invalidation that finds nothing writes nothing (R10), a remembered failure of the old ID is forgotten
- [ ] PRE-002-T05 [US1] App: `PresetThumbnailModel.invalidate(presetID:keepingContentHash:)` evicting in-memory pictures of that preset's other hashes (`Apps/projectM-iOS/Coordinators/PresetThumbnailModel.swift`); `UserPresetsCoordinator.refresh()` diffs the playable ID → hash map and invalidates changed or removed presets (`Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift`); `PresetThumbnailView.requestID(for:playable:)` as a static used by `.task(id:)` (`Apps/projectM-iOS/Views/PresetThumbnailView.swift`)
- [ ] PRE-002-T06 [US1] App unit test `Apps/projectM-iOS/Tests/PresetThumbnailInvalidationAppTests.swift`: two user presets and a built-in preset cached; saving an edit with new text removes exactly the edited preset's old file and changes its row request ID; the others keep their files; a rename-only save keeps its file and request ID (S5)

## Phase 4: User Story 2 - A removed preset leaves nothing behind (P1)

- [ ] PRE-002-T07 [US2] Package test (S2): removing one of three presets (`invalidate(…, keepingContentHash: nil)`) removes 1 file and entry, 2 remain; `retainOnly` drops entries of unlisted presets and of listed presets with another hash, in `PresetThumbnailInvalidationTests.swift`
- [ ] PRE-002-T08 [US2] App: `PresetThumbnailModel.collectGarbage(listing:)` and its one call from `PresetCoordinator.attach(_:)` (`Apps/projectM-iOS/Coordinators/PresetCoordinator.swift`); app test: removing a user preset removes its file (the same refresh diff covers quarantine and copies held for the unlock, R2); the launch collection removes an entry for a preset not listed

## Phase 5: User Story 3 - A new renderer redraws every picture (P2)

- [ ] PRE-002-T09 [US3] Fixture `Packages/PresetLibrary/Tests/PresetLibraryTests/ThumbnailFixtures/index-renderer-v1.json` (entries for A and B at renderer version 1) and a test opening it with a version 2 spec: 0 entries, 0 old files, each requested preset renders once (S3)

## Phase 6: Polish

- [ ] PRE-002-T10 Type-check budget (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`) on the app build, the full PresetLibrary package suite, the repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`), the Linux shape of PresetLibrary (no Apple-only API in the new code; CI's Linux job runs the package, R9), PosterBoard count after; delete the simulator, derived data and the `Build` link

## Dependencies

T01 → T02 → T03 → (T04, T07, T09 package tests) and T05 → T06, T08. US1 is the MVP; US2 reuses T03;
US3 needs only T03 (and PRE-001's open-time drop).

## Parallel examples

- T04 and T07 share one test file, so they run in sequence; T09's fixture and T05's app glue touch different files and can proceed in parallel.

## Implementation strategy

Package first (T02-T04, T07, T09: the acceptance on the host), then the app glue and its test
(T05, T06, T08), then polish.
