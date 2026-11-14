# Tasks: MED-013 Media Asset Relinking

**Input**: [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md),
[contracts/media-relink.md](contracts/media-relink.md), [research.md](research.md)

Tests are requested by the brief (acceptance, scan, bounds, atomic rewrite, erase, one UI test).
Budgets (owner rule 7): unit tests about 1-2 s, package suites under 1 minute, the UI test under 30 s.

## Phase 1: Setup

- [X] MED-013-T01 Create the feature's own simulator "MED13 iPhone 17" (iOS 27.2), initialize the preset submodules, `xcodegen generate`, keep the `Build` link, and count PosterBoard reports before any run. — Verified 2026-11-14: simulator "MED13 iPhone 17" (301AF453) created on iOS 27.2, preset submodules initialized, `xcodegen generate`, `Build` link present, PosterBoard reports 25 before.

## Phase 2: Foundational (packages; blocks every story)

- [X] MED-013-T02 Registry `released` list and relink operations in `Packages/LocalPortability/Sources/LocalPortability/ContentAddressedMediaFolder.swift` and `ContentAddressedMediaFolder+Relink.swift` (`knownPayloadName`, `adoptKnown`, `restorePayload`, `forget`; contract L1; research MED-013-D1). — Verified 2026-11-14: `swift test --package-path Packages/LocalPortability` 120/120 (MediaRelinkFolderTests: released list, bound, older registry, adoption, restore, forget); also with `-DLOCALPORTABILITY_NO_CRYPTOKIT` (the Linux hashing path) 12/12.
- [X] MED-013-T03 [P] Bounded folder scan `Packages/LocalPortability/Sources/LocalPortability/MediaFolderScan.swift` (contract L2; research MED-013-D3). — Verified 2026-11-14: MediaRelinkFolderTests scan tests (match in a subfolder, links not followed, each bound, early stop) pass.
- [X] MED-013-T04 [P] Package tests `Packages/LocalPortability/Tests/LocalPortabilityTests/MediaRelinkFolderTests.swift`: released entries recorded and bounded, re-intern of the same bytes resolves a deleted payload, adoption of a released identifier, restore from a file verifies the hash, forget; scan finds a match, ignores non-matching, hidden and linked files, and stops at each bound. — Verified 2026-11-14: MediaRelinkFolderTests 12 tests in 0.6 s.
- [X] MED-013-T05 [P] Scene references `Packages/SceneFormat/Sources/SceneFormat/SceneMediaReferences.swift` and tests `SceneMediaReferenceTests.swift` (photo, slides, logo, video; unknown fields kept; other store untouched) (contract L3). — Verified 2026-11-14: `swift test --package-path Packages/SceneFormat` 143/143 (SceneMediaReferenceTests 3; SceneSourceSafetyTests lists the new file).
- [X] MED-013-T06 Show store usage and atomic rewrite `Packages/ShowControl/Sources/ShowStorage/ShowMediaRelink.swift` and tests `ShowMediaRelinkTests.swift` (usage counts; rewrite of several scenes; a fault at every step leaves every file byte for byte; unreadable scenes counted; SCN-013 backup kept) (contract L4; research MED-013-D4). — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` 71/71 (ShowMediaRelinkTests 4: usage, rewrite and reload, a fault at each of the 4 steps for each scene leaves every file byte for byte, unreadable scenes and leftovers). The SCN-013 backup step reuses `saveScene`'s `keepOriginalIfMigrated` and is covered by the fault test; no migrated-file fixture was added.
- [X] MED-013-T07 FILE-011: a scenes-only erase forgets the identifiers it releases in `Packages/LibraryBackup/Sources/LibraryBackup/LibraryEraser.swift`; test in `LibraryEraseReferenceTests.swift` (scenes-only erase leaves no released entry; media erase leaves no registry) (MED-013-R9). — Verified 2026-11-14: `swift test --package-path Packages/LibraryBackup` 68/68 (LibraryEraseReferenceTests: no released entry after a scenes-only erase; no registry after a media erase).

## Phase 3: User Story 1 — placeholder and checksum relink (P1, MVP)

- [X] MED-013-T08 [US1] `Apps/projectM-iOS/Coordinators/MediaRelinkService.swift`: missing list from the show's scenes and cues, checksum relink, folder scan under security scope (contract L5). — Verified 2026-11-14: MediaRelinkAcceptanceTests on MED13 (missing list, checksum relink, folder scan).
- [X] MED-013-T09 [US1] `Apps/projectM-iOS/Coordinators/MissingMediaCoordinator.swift` and `AppCoordinator+MissingMedia.swift`: items, busy state, report, placeholder, announcements on the library lane; adopt after photo and video imports; placeholder set when a cue applies a scene with missing media (MED-013-R2, R4, R8). — Verified 2026-11-14: MediaRelinkAcceptanceTests (placeholder through the SHOW-001 cue and SCN-012 report, mediaImported announcement) and MissingMediaUITests on MED13.
- [X] MED-013-T10 [US1] `Apps/projectM-iOS/Views/MissingMediaView.swift` (screen and placeholder tile), Storage link in `StorageUsageView`, `SettingsView` and `VisualizerView` one-line edits; register the view in `scripts/check_status_events.py` (MED-013-R11, contract L6). — Verified 2026-11-14: MissingMediaUITests on MED13 (placeholder, screen, Find, Done); `check_status_events.py` OK with both files registered; the Storage row builds and CacheCleanupUITests and LibraryEraseUITests still pass on MED13.

## Phase 4: User Story 2 — replacement (P1)

- [X] MED-013-T11 [US2] Replacement in `MediaRelinkService` (stage through the store, rewrite scenes, rewrite settings values, discard on failure) and the Relink… file importer in the view (image types for a photo item, movie types for a video item) (MED-013-R6, R7). — Verified 2026-11-14: MediaRelinkAcceptanceTests.testReplacementRewritesEveryReferenceAtomicallyAndPersists and testAFailingRewriteChangesNothingAndDiscardsTheStagedCopy. The Files picker itself is not driven by a test (pickers cannot be automated).
- [X] MED-013-T12 [US1][US2] Acceptance test `Apps/projectM-iOS/Tests/MediaRelinkAcceptanceTests.swift`: scenes A and B and a cue use photo P, B's slideshow includes P; delete P's payload; the placeholder state is set and the missing list shows P with 2 scenes and 2 cues; checksum relink resolves every reference; separately replacement rewrites A, B, the cue's scene and the slideshow to the new identifier and the change survives a reload from disk; a failing rewrite discards the staged copy and changes nothing (MED-013-S1-S3). — Verified 2026-11-14: MediaRelinkAcceptanceTests 6/6 in 0.2 s on MED13; projectM-iOSTests 701/701 (36.2 s).

## Phase 5: User Story 3 — limits and erase (P2)

- [X] MED-013-T13 [US3] App-level erase interaction and folder scan in `MediaRelinkAcceptanceTests`: after a released identifier is forgotten the row says checksum unknown; a folder scan finds P's bytes among other files and ignores the rest (MED-013-S4). — Verified 2026-11-14: MediaRelinkAcceptanceTests.testFindInFolderRestoresAMatchAndIgnoresOtherFiles and testAfterAnEraseForgetsTheIdentifierOnlyReplacementIsLeft.

## Phase 6: Polish

- [X] MED-013-T14 UI test `Apps/projectM-iOS/UITests/MissingMediaUITests.swift` with the DEBUG seed `Apps/projectM-iOS/Debug/UITestMissingMediaFixture.swift` (`-uitestMissingMediaSeed`): open Missing Media from Settings → Storage, see the photo used by 2 scenes, Find Missing Media in Folder… (fixture folder), the list empties; under 30 s (MED-013-S5). — Verified 2026-11-14: MissingMediaUITests passed on MED13 in 18.6 s and 11.0 s.
- [X] MED-013-T15 Repo checks (compliance, docs, motion, permissions, status events, script tests), privacy manifest and network symbol checks on the Debug app, type-check budget, no new UserDefaults keys (grep the diff), PosterBoard count after; update the spec status; delete the simulator and derived data. — Verified 2026-11-14: compliance, validate_docs, motion, permissions, status events OK; test_scripts 153 OK; check_privacy_manifest and check_network_symbols OK on the Debug simulator app; type-check: no new function body over 300 ms or expression over 200 ms (AppCoordinator.init 401-490 ms and VisualizerView.layers 340-352 ms exceed 300 ms on the loaded Mac with and without this change, measured against the baseline file); no new UserDefaults keys (diff grep); PosterBoard reports 25 before and after; simulator MED13 and derived data deleted.

## Dependencies

T01 → T02 → (T03, T04, T05 in parallel) → T06 → T07 → T08 → T09 → T10 → T11 → T12 → T13 → T14 → T15.

## Implementation strategy

MVP = Phases 1-3 (placeholder, list, checksum relink). Replacement (US2) shares the service; US3 is
tests over the same code.
