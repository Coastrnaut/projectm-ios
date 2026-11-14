# Tasks: SCN-004 Scene Folder Organization

**Input**: [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md),
[contracts/scene-folders.md](contracts/scene-folders.md), [research.md](research.md)

Tests are requested by the roadmap row (schema round trip, integration, simulator). Budgets (owner
rule 7): unit tests about 1-2 s, package suites under 1 minute, the UI test under 30 s.

## Phase 1: Setup

- [X] SCN-004-T01 Create the feature's own simulator "SCN4 iPhone 17" (iOS 27.2), `xcodegen generate`, link `Build` to the main checkout's xcframeworks if missing, and count PosterBoard reports before any run. — Verified 2026-11-14: simulator SCN4 (063ABDB3) created on iOS 27.2, `xcodegen generate`, `Build` link already present, PosterBoard reports 25 before.

## Phase 2: Foundational (model and file format; blocks every story)

- [X] SCN-004-T02 Implement `SceneFolder`, `SceneFolderTree` and `SceneFolderError` in `Packages/ShowControl/Sources/ShowControl/SceneFolders.swift`: names "Trimmed, 1-80 characters, one line; unique among siblings (folded: case, accents, width)"; "≤ 256" folders; depth ≤ 5; create, rename, move folder (cycle, depth, name checks), move scene, delete (children to parent, " 2"/" 3" suffix), children/path/depth/height queries (research SCN-004-D2; contract F2, F3). — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` (SceneFolderTreeTests 8/8).
- [X] SCN-004-T03 Add `folders` to `ShowCueList` with forwarding operations (`moveScene` refuses a scene no cue refers to) in `Packages/ShowControl/Sources/ShowControl/ShowCueList.swift`. — Verified 2026-11-14: ShowFolderDocumentTests.testMovingASceneThatNoCueShowsIsRefused and the app acceptance test.
- [X] SCN-004-T04 Encode and decode the optional `folders` / `sceneFolders` keys (written only when non-empty, deterministic order, assignments pruned to the cues' scenes) and repair damaged data with `droppedFolders` / `droppedFolderAssignments` warnings in `Packages/ShowControl/Sources/ShowControl/ShowDocument.swift` (research SCN-004-D3, D4; contract F4). — Verified 2026-11-14: ShowFolderDocumentTests 6/6 (round trip, legacy bytes, repair warnings).
- [X] SCN-004-T05 [P] Package tests for the tree rules (create, rename, move, cycle rejection, depth, name collisions, delete re-parenting with suffix, limit) in `Packages/ShowControl/Tests/ShowControlTests/SceneFolderTreeTests.swift`. — Verified 2026-11-14: SceneFolderTreeTests 8 tests pass in 0.11 s.
- [X] SCN-004-T06 [P] Package tests for the file format: round trip, determinism, a legacy version 1 fixture without folder keys decoding to an empty tree and re-encoding byte for byte, damaged folder data repaired with warnings, a `ShowStore` save → reload keeping folders with scene file bytes unchanged, and a FILE-004 `installImportedScenes` keeping the existing folders with the imported scene at the top level (SCN-004-R9), in `Packages/ShowControl/Tests/ShowControlTests/ShowFolderDocumentTests.swift`. — Verified 2026-11-14: ShowFolderDocumentTests 6 tests pass in 0.03 s; ShowControl 56/56.

## Phase 3: User Story 1 — sort scenes into folders (P1, MVP)

**Independent test**: move a scene from A to B/C; its ID and file are unchanged, its cue applies the same scene, the switcher resolves it, and a reload keeps the assignment.

- [X] SCN-004-T07 [US1] Folder operations in `Apps/projectM-iOS/Coordinators/ShowCoordinator.swift`: create, rename, move folder, move scene, delete, `folderPath(ofScene:)`, `firstCue(ofScene:)`, `goToScene(_:)`; save after each change; announce results and refusals through `announceLibrary`; Duplicate Scene puts the copy in its source's folder (SCN-004-R12). Wire `announceLibrary` to the shared announcer's `.library` lane in `AppCoordinator+Show.swift` (one line). — Verified 2026-11-14: SceneFolderAcceptanceTests 6/6 on SCN4; wired in `AppCoordinator+Show.swift` (one line).
- [X] SCN-004-T08 [US1] `Apps/projectM-iOS/Views/SceneFoldersView.swift`: one level (folders then scenes, sorted by name), NavigationLink drill-down, New Folder alert, swipe actions / context menus / VoiceOver actions, Move to… sheet with Top Level and the indented tree (refused destinations disabled), delete confirmation for a non-empty folder; identifiers per contract F5. Link row `showSceneFoldersLink` in `Apps/projectM-iOS/Views/ShowEditorView.swift`. — Verified 2026-11-14: SceneFoldersUITests on SCN4 (28.1 s and 28.9 s).
- [X] SCN-004-T09 [US1] UIX-002 folder path: `folderPath` on `SceneSwitcherEntry`, VoiceOver value ", folder <path>", filter match on the path in `Apps/projectM-iOS/Coordinators/SceneSwitcher.swift`; subtitle in `Apps/projectM-iOS/Views/SceneSwitcherView.swift` (contract F6). — Verified 2026-11-14: SceneSwitcherTests.testEntriesCarryTheFolderPathAndSearchMatchesItAfterNameMatches and the acceptance test.
- [X] SCN-004-T10 [US1] Acceptance test `Apps/projectM-iOS/Tests/SceneFolderAcceptanceTests.swift`: nested folders, move a scene from A to B/C; scene ID and file bytes unchanged; a cue referencing it still resolves and applies (the applied document's ID); switcher entry resolves with folder path; a coordinator reloaded from the same store keeps the assignment; duplicate lands in the source's folder; an unreadable scene keeps its folder and can be moved (spec Edge Cases). Plus switcher folder-path cases in `Apps/projectM-iOS/Tests/SceneSwitcherTests.swift`. — Verified 2026-11-14: SceneFolderAcceptanceTests 6 tests in 0.06 s; projectM-iOSTests 616/616 (42.2 s).
- [X] SCN-004-T11 [US1] UI test `Apps/projectM-iOS/UITests/SceneFoldersUITests.swift` (under 30 s): with `-uitestShowSeed`, open Scene Folders, create folder "Set A", move "Opening" into it, open "Set A" and see "Opening". — Verified 2026-11-14: SceneFoldersUITests passed twice on SCN4, 28.1 s and 28.9 s.

## Phase 4: User Story 2 — keep the tree tidy (P2)

- [X] SCN-004-T12 [US2] Coordinator tests for folder rename, move refusals (cycle, depth, name taken) leaving the show unchanged and announced, a move to the scene's current folder writing nothing, and folder deletion re-parenting with every cue still resolving, in `Apps/projectM-iOS/Tests/SceneFolderAcceptanceTests.swift`. — Verified 2026-11-14: SceneFolderAcceptanceTests refusal, deletion and no-op tests pass (depth refusals in SceneFolderTreeTests).

## Phase 5: User Story 3 — survive backup and upgrades (P2)

- [X] SCN-004-T13 [P] [US3] Backup round trip test: a show with folders read into `LibraryContents`, written as a backup, restored exactly, decodes with the same tree and assignments, in `Packages/LibraryBackup/Tests/LibraryBackupTests/` (new file `LibraryBackupSceneFolderTests.swift`). — Verified 2026-11-14: LibraryBackupSceneFolderTests 1/1; LibraryBackup 45/45.

## Phase 6: Polish

- [X] SCN-004-T14 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbol checks on the Debug app, type-check budget, PosterBoard counts; spec status; delete the simulator, derived data and the `Build` link. — Verified 2026-11-14: all six repo checks OK (script tests 153, 1 skipped); `check_privacy_manifest.py` and `check_network_symbols.py` OK on the Debug app; no new file over the type-check limits (warn-long flags); PosterBoard reports 25 before and after; regression UI tests SceneDuplicate, SceneSwitcher (4) and ShowCue (2) pass; simulator SCN4 and derived data deleted; the `Build` link was there before this feature (made by the run), so it was left in place.

## Dependencies

T01 → T02 → T03 → T04 → (T05, T06 in parallel) → T07 → T08, T09 → T10, T11, T12; T13 needs only T04.
US1 is the MVP; US2 and US3 add tests on the same code.
