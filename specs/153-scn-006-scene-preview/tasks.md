# Tasks: SCN-006 Scene Preview Image

**Input**: [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md),
[contracts/scene-preview.md](contracts/scene-preview.md), [research.md](research.md)

Tests are requested by the brief (acceptance with an injected capture, prune on delete, placeholder,
relaunch, one UI test). Budgets (owner rule 7): unit tests about 1-2 s, package suites under 1 minute,
the UI test under 30 s.

## Phase 1: Setup

- [X] SCN-006-T01 Create the feature's own simulator "SCN6 iPhone 17" (iOS 27.2), `xcodegen generate`, keep the `Build` link, and count PosterBoard reports before any run. — Verified 2026-11-14: simulator SCN6 (3691DFC9) on iOS 27.2, `xcodegen generate`, `Build` link present, preset submodules initialized, PosterBoard reports 25 before.

## Phase 2: Foundational (the store; blocks every story)

- [X] SCN-006-T02 Implement `ScenePreviewKey` and the `ScenePreviewStore` actor in `Packages/PresetLibrary/Sources/PresetLibrary/Thumbnails/ScenePreviewStore.swift`, reusing `PresetThumbnailIndex` (repair, `staleIDs`, `unlistedIDs`, `removeEntries`) unchanged (research SCN-006-D1, D2; contract P1). — Verified 2026-11-14: ScenePreviewStoreTests 5/5; PRE-001/PRE-002 files not changed (`git diff --stat`).
- [X] SCN-006-T03 [P] Package tests in `Packages/PresetLibrary/Tests/PresetLibraryTests/ScenePreviewStoreTests.swift`: key determinism and hash, store keeps one entry per scene, invalidate leaves neighbours, retainOnly prunes unlisted and changed scenes, reopen keeps entries (relaunch), damaged index repaired, cleared folder recreated and marked excluded from backup (Darwin); PRE-001's suites still pass. — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary` 264 tests, 0 failures (27.8 s); ScenePreviewStoreTests 5 tests in 0.012 s.

## Phase 3: User Story 1 and 2 — previews captured, keyed and invalidated (P1, MVP)

**Independent test**: with an injected capture, save and apply scenes, edit one, remove one, reopen.

- [X] SCN-006-T04 [US1] `Apps/projectM-iOS/Coordinators/ScenePreviewModel.swift` (contract P2): hashes, NSCache, `revision`, `sceneSaved`, `sceneApplied` (settle, guard SCN-006-R3, token), `scenesChanged`, `reconcile`, `image(forScene:)`. — Verified 2026-11-14: ScenePreviewAcceptanceTests 6/6 on SCN6 (save, edit, prune, relaunch, guard, crop).
- [X] SCN-006-T05 [US1] `Apps/projectM-iOS/Coordinators/ScenePreviewCapture.swift` (contract P3): `LiveScenePreviewCapture` over REC-001's `FrameCaptureSource` (1 s timeout, crop and scale to 192 × 108, PNG off the main actor) and DEBUG `FixtureScenePreviewCapture` (`-uitestScenePreviewFixture`). — Verified 2026-11-14: testPreviewPictureIsCroppedAndScaled (192 × 108 PNG, centre crop); fixture drives ScenePreviewUITests. The live REC-001 grab itself is not exercised by a test here (REC-001's own tests cover it).
- [X] SCN-006-T06 [US2] `ShowCoordinator`: `sceneFilesChanged` hook after Add, Rename, Duplicate and cue removal; `sceneContentHashes()`. — Verified 2026-11-14: testEditInvalidates… (rename path) and testRemovingTheLastCuePrunesThePreview on SCN6; SceneTagAcceptanceTests 4/4 still pass.
- [X] SCN-006-T07 [US1] Wiring in `Apps/projectM-iOS/Coordinators/AppCoordinator+ScenePreviews.swift`, one property in `AppCoordinator.swift`, the apply and Add Current Scene calls in `AppCoordinator+Show.swift`, launch reconciliation. — Verified 2026-11-14: ScenePreviewUITests on SCN6 (apply through the switcher captures after the settle); projectM-iOSTests 701/701 (91 s).
- [X] SCN-006-T08 [US1] [US2] Acceptance tests `Apps/projectM-iOS/Tests/ScenePreviewAcceptanceTests.swift`: (1) save S → preview equals the captured image, keyed to S's hash; (2) edit S (parameter change, saved) → old entry and file gone, placeholder, next apply keyed to the new hash; (3) neighbours untouched; removing S's cue prunes it; placeholder when missing; relaunch (new model over the same folder) shows the same preview; the guard drops a capture when the look changed or another scene was applied during the settle; a second apply captures nothing. — Verified 2026-11-14: ScenePreviewAcceptanceTests 6 tests in 0.08 s on SCN6.

## Phase 4: User Story 3 — previews in the lists (P2)

- [X] SCN-006-T09 [US3] `Apps/projectM-iOS/Views/ScenePreviewView.swift` (contract P4) and the tile in `SceneSwitcherView` rows and `SceneFoldersView` scene rows; labels, values and identifiers unchanged. — Verified 2026-11-14: ScenePreviewUITests (label and value unchanged); SceneFoldersUITests passes (21.8 s); SceneSwitcherUITests 4/4 (testTypeFilterAndRecallWithinBudget failed once on its 2 s announcement poll, then passed twice in a rerun).
- [X] SCN-006-T10 [US3] UI test `Apps/projectM-iOS/UITests/ScenePreviewUITests.swift` (under 30 s): with `-uitestShowSeed -uitestScenePreviewFixture`, choose cue 2 in the switcher, reopen it: row 2 shows `scenePreview:<id>`, row 3 a placeholder, row 2's label and value unchanged (SCN-006-R9); the Folders tile shares the view and is covered by a build and the existing SceneFoldersUITests. — Verified 2026-11-14: ScenePreviewUITests passed twice on SCN6, 17.7 s and 11.0 s.

## Phase 5: Polish

- [X] SCN-006-T11 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), `check_privacy_manifest.py` and `check_network_symbols` on the Debug app, type-check budget; confirm SCN-006-R10 (the folder is under Storage's Caches root `Library/Caches`, FILE-005's backup and FILE-001 archives read only the show folder, no new UserDefaults key), PosterBoard count after, delete the simulator and derived data; spec status updated. — Verified 2026-11-14: compliance, validate_docs, motion policy, permission catalog, status events OK; test_scripts 153 OK; check_privacy_manifest and check_network_symbols OK on the Debug app; no new type-check warnings in changed code (SceneSwitcherView.swift:27, an unchanged expression, measured 204 ms once under load); PosterBoard 25 before, 25 after; simulator and derived data deleted.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1-R2 T04/T07/T08; R3 T04/T08; R4-R6 T02/T03/T06/T08; R7 T02/T03; R8-R9 T09/T10; R10 T03/T11; R11 T05/T10. Three fixes applied: R10 verification added to T11, backup exclusion to T03, R9 and the Folders tile to T10. No contradictions with the constitution.
