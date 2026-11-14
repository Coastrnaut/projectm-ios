# Tasks: SCN-004 Scene Folder Organization

**Input**: [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md),
[contracts/scene-folders.md](contracts/scene-folders.md), [research.md](research.md)

Tests are requested by the roadmap row (schema round trip, integration, simulator). Budgets (owner
rule 7): unit tests about 1-2 s, package suites under 1 minute, the UI test under 30 s.

## Phase 1: Setup

- [ ] SCN-004-T01 Create the feature's own simulator "SCN4 iPhone 17" (iOS 27.2), `xcodegen generate`, link `Build` to the main checkout's xcframeworks if missing, and count PosterBoard reports before any run.

## Phase 2: Foundational (model and file format; blocks every story)

- [ ] SCN-004-T02 Implement `SceneFolder`, `SceneFolderTree` and `SceneFolderError` in `Packages/ShowControl/Sources/ShowControl/SceneFolders.swift`: names "Trimmed, 1-80 characters, one line; unique among siblings (folded: case, accents, width)"; "≤ 256" folders; depth ≤ 5; create, rename, move folder (cycle, depth, name checks), move scene, delete (children to parent, " 2"/" 3" suffix), children/path/depth/height queries (research SCN-004-D2; contract F2, F3).
- [ ] SCN-004-T03 Add `folders` to `ShowCueList` with forwarding operations (`moveScene` refuses a scene no cue refers to) in `Packages/ShowControl/Sources/ShowControl/ShowCueList.swift`.
- [ ] SCN-004-T04 Encode and decode the optional `folders` / `sceneFolders` keys (written only when non-empty, deterministic order, assignments pruned to the cues' scenes) and repair damaged data with `droppedFolders` / `droppedFolderAssignments` warnings in `Packages/ShowControl/Sources/ShowControl/ShowDocument.swift` (research SCN-004-D3, D4; contract F4).
- [ ] SCN-004-T05 [P] Package tests for the tree rules (create, rename, move, cycle rejection, depth, name collisions, delete re-parenting with suffix, limit) in `Packages/ShowControl/Tests/ShowControlTests/SceneFolderTreeTests.swift`.
- [ ] SCN-004-T06 [P] Package tests for the file format: round trip, determinism, a legacy version 1 fixture without folder keys decoding to an empty tree and re-encoding byte for byte, damaged folder data repaired with warnings, and a `ShowStore` save → reload keeping folders with scene file bytes unchanged, in `Packages/ShowControl/Tests/ShowControlTests/ShowFolderDocumentTests.swift`.

## Phase 3: User Story 1 — sort scenes into folders (P1, MVP)

**Independent test**: move a scene from A to B/C; its ID and file are unchanged, its cue applies the same scene, the switcher resolves it, and a reload keeps the assignment.

- [ ] SCN-004-T07 [US1] Folder operations in `Apps/projectM-iOS/Coordinators/ShowCoordinator.swift`: create, rename, move folder, move scene, delete, `folderPath(ofScene:)`, `firstCue(ofScene:)`, `goToScene(_:)`; save after each change; announce results and refusals through `announceLibrary`; Duplicate Scene puts the copy in its source's folder (SCN-004-R12). Wire `announceLibrary` to the shared announcer's `.library` lane in `AppCoordinator.swift` (one line).
- [ ] SCN-004-T08 [US1] `Apps/projectM-iOS/Views/SceneFoldersView.swift`: one level (folders then scenes, sorted by name), NavigationLink drill-down, New Folder alert, swipe actions / context menus / VoiceOver actions, Move to… sheet with Top Level and the indented tree (refused destinations disabled), delete confirmation for a non-empty folder; identifiers per contract F5. Link row `showSceneFoldersLink` in `Apps/projectM-iOS/Views/ShowEditorView.swift`.
- [ ] SCN-004-T09 [US1] UIX-002 folder path: `folderPath` on `SceneSwitcherEntry`, VoiceOver value ", folder <path>", filter match on the path in `Apps/projectM-iOS/Coordinators/SceneSwitcher.swift`; subtitle in `Apps/projectM-iOS/Views/SceneSwitcherView.swift` (contract F6).
- [ ] SCN-004-T10 [US1] Acceptance test `Apps/projectM-iOS/Tests/SceneFolderAcceptanceTests.swift`: nested folders, move a scene from A to B/C; scene ID and file bytes unchanged; a cue referencing it still resolves and applies (the applied document's ID); switcher entry resolves with folder path; a coordinator reloaded from the same store keeps the assignment; duplicate lands in the source's folder. Plus switcher folder-path cases in `Apps/projectM-iOS/Tests/SceneSwitcherTests.swift`.
- [ ] SCN-004-T11 [US1] UI test `Apps/projectM-iOS/UITests/SceneFoldersUITests.swift` (under 30 s): with `-uitestShowSeed`, open Scene Folders, create folder "Set A", move "Opening" into it, open "Set A" and see "Opening".

## Phase 4: User Story 2 — keep the tree tidy (P2)

- [ ] SCN-004-T12 [US2] Coordinator tests for folder rename, move refusals (cycle, depth, name taken) leaving the show unchanged and announced, and folder deletion re-parenting with every cue still resolving, in `Apps/projectM-iOS/Tests/SceneFolderAcceptanceTests.swift`.

## Phase 5: User Story 3 — survive backup and upgrades (P2)

- [ ] SCN-004-T13 [P] [US3] Backup round trip test: a show with folders read into `LibraryContents`, written as a backup, restored exactly, decodes with the same tree and assignments, in `Packages/LibraryBackup/Tests/LibraryBackupTests/` (new file `LibraryBackupSceneFolderTests.swift`).

## Phase 6: Polish

- [ ] SCN-004-T14 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbol checks on the Debug app, type-check budget, PosterBoard counts; spec status; delete the simulator, derived data and the `Build` link.

## Dependencies

T01 → T02 → T03 → T04 → (T05, T06 in parallel) → T07 → T08, T09 → T10, T11, T12; T13 needs only T04.
US1 is the MVP; US2 and US3 add tests on the same code.
