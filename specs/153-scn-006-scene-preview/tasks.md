# Tasks: SCN-006 Scene Preview Image

**Input**: [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md),
[contracts/scene-preview.md](contracts/scene-preview.md), [research.md](research.md)

Tests are requested by the brief (acceptance with an injected capture, prune on delete, placeholder,
relaunch, one UI test). Budgets (owner rule 7): unit tests about 1-2 s, package suites under 1 minute,
the UI test under 30 s.

## Phase 1: Setup

- [ ] SCN-006-T01 Create the feature's own simulator "SCN6 iPhone 17" (iOS 27.2), `xcodegen generate`, keep the `Build` link, and count PosterBoard reports before any run.

## Phase 2: Foundational (the store; blocks every story)

- [ ] SCN-006-T02 Implement `ScenePreviewKey` and the `ScenePreviewStore` actor in `Packages/PresetLibrary/Sources/PresetLibrary/Thumbnails/ScenePreviewStore.swift`, reusing `PresetThumbnailIndex` (repair, `staleIDs`, `unlistedIDs`, `removeEntries`) unchanged (research SCN-006-D1, D2; contract P1).
- [ ] SCN-006-T03 [P] Package tests in `Packages/PresetLibrary/Tests/PresetLibraryTests/ScenePreviewStoreTests.swift`: key determinism and hash, store keeps one entry per scene, invalidate leaves neighbours, retainOnly prunes unlisted and changed scenes, reopen keeps entries (relaunch), damaged index repaired, cleared folder recreated; PRE-001's suites still pass.

## Phase 3: User Story 1 and 2 — previews captured, keyed and invalidated (P1, MVP)

**Independent test**: with an injected capture, save and apply scenes, edit one, remove one, reopen.

- [ ] SCN-006-T04 [US1] `Apps/projectM-iOS/Coordinators/ScenePreviewModel.swift` (contract P2): hashes, NSCache, `revision`, `sceneSaved`, `sceneApplied` (settle, guard SCN-006-R3, token), `scenesChanged`, `reconcile`, `image(forScene:)`.
- [ ] SCN-006-T05 [US1] `Apps/projectM-iOS/Coordinators/ScenePreviewCapture.swift` (contract P3): `LiveScenePreviewCapture` over REC-001's `FrameCaptureSource` (1 s timeout, crop and scale to 192 × 108, PNG off the main actor) and DEBUG `FixtureScenePreviewCapture` (`-uitestScenePreviewFixture`).
- [ ] SCN-006-T06 [US2] `ShowCoordinator`: `sceneFilesChanged` hook after Add, Rename, Duplicate and cue removal; `sceneContentHashes()`.
- [ ] SCN-006-T07 [US1] Wiring in `Apps/projectM-iOS/Coordinators/AppCoordinator+ScenePreviews.swift`, one property in `AppCoordinator.swift`, the apply and Add Current Scene calls in `AppCoordinator+Show.swift`, launch reconciliation.
- [ ] SCN-006-T08 [US1] [US2] Acceptance tests `Apps/projectM-iOS/Tests/ScenePreviewAcceptanceTests.swift`: (1) save S → preview equals the captured image, keyed to S's hash; (2) edit S (parameter change, saved) → old entry and file gone, placeholder, next apply keyed to the new hash; (3) neighbours untouched; removing S's cue prunes it; placeholder when missing; relaunch (new model over the same folder) shows the same preview; the guard drops a capture when the look changed or another scene was applied during the settle; a second apply captures nothing.

## Phase 4: User Story 3 — previews in the lists (P2)

- [ ] SCN-006-T09 [US3] `Apps/projectM-iOS/Views/ScenePreviewView.swift` (contract P4) and the tile in `SceneSwitcherView` rows and `SceneFoldersView` scene rows; labels, values and identifiers unchanged.
- [ ] SCN-006-T10 [US3] UI test `Apps/projectM-iOS/UITests/ScenePreviewUITests.swift` (under 30 s): with `-uitestShowSeed -uitestScenePreviewFixture`, choose cue 2 in the switcher, reopen it: row 2 shows `scenePreview:<id>`, row 3 a placeholder, row 2's label unchanged.

## Phase 5: Polish

- [ ] SCN-006-T11 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), `check_privacy_manifest.py` and `check_network_symbols` on the Debug app, type-check budget, PosterBoard count after, delete the simulator and derived data; spec status updated.
