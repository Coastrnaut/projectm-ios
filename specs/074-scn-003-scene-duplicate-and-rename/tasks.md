# Tasks: SCN-003 Scene Duplicate and Rename

**Input**: Design documents from `specs/074-scn-003-scene-duplicate-and-rename/` (spec, plan, research,
data-model, contracts/scene-duplicate-rename.md, quickstart)

**Tests**: requested by the spec (SCN-003-S1 to S6) and the roadmap row ("schema round trip +
integration + simulator"). Budgets (owner rule 7): unit ≤ 10 s, suite < 1 min, UI test < 30 s,
property test ≤ 1 s.

A task is ticked `[X]` only when verified, with " — Verified <date>: <how>".

## Phase 1: Setup

- [X] SCN-003-T01 Add ParameterGraph as a test dependency of ShowControlTests (registry for `liveState`) in Packages/ShowControl/Package.swift — Verified 2026-11-13: `swift test --package-path Packages/ShowControl` 25/25 on the host (0.19 s) and in the Linux shape (0.27 s); ShowSceneEditTests builds a ParameterRegistry

## Phase 2: Foundational (scene-level rule, blocks every story)

- [X] SCN-003-T02 Implement `SceneEditError`, `SceneDocument.isValidName`, `normalizedName` (trim; "1…120 characters", no control characters), `copyName` ("<name> copy" within 120), `renamed(to:)` and `duplicated(newID:name:)` (canonical uppercase UUID, ≠ original) in Packages/SceneFormat/Sources/SceneFormat/SceneEditing.swift; make the validator's name check call `isValidName` in Packages/SceneFormat/Sources/SceneFormat/SceneValidation.swift — Verified 2026-11-13: `swift test --package-path Packages/SceneFormat` 48/48 on the host (1.7 s) and in the Linux shape (1.3 s); SceneValidationTests and SceneSourceSafetyTests still pass with the shared name rule
- [X] SCN-003-T03 [P] Tests in Packages/SceneFormat/Tests/SceneFormatTests/SceneEditingTests.swift: name table (valid, trimmed, empty, spaces only, 120 and 121 characters, emoji graphemes, tab, newline inside, NUL, DEL) (S4); copyName shortening; duplicate of the all-kinds fixture: distinct IDs, both decode from their own bytes, `liveState` equal, bytes equal after putting the ID and name back (S1 at the scene level); rename keeps the ID (S2); invalid and same IDs refused; fixed-seed property test over 200 generated scenes (S3, ≤ 1 s) — Verified 2026-11-13: SceneEditingTests 7/7 (0.31 s; property test 200 scenes 0.30 s) on the host and Linux shape

## Phase 3: User Story 1 — Duplicate a cue's scene (P1)

**Goal**: Duplicate Scene in Settings → Show stores a copy under a new ID and inserts its cue after the source cue.
**Independent test**: SCN-003-S1 in ShowSceneEditTests; app path in ShowCoordinatorTests.

- [X] SCN-003-T04 [US1] `ShowCueList.insert(sceneID:label:after:cueID:)` (position unchanged; errors as `append` plus `unknownCue`) and `copyLabel` ("<label> copy" within 80) in Packages/ShowControl/Sources/ShowControl/ShowCueList.swift — Verified 2026-11-13: ShowSceneEditTests.testInsertGoesRightAfterItsCueAndKeepsThePosition; `swift test --package-path Packages/ShowControl` 25/25 on the host (0.19 s) and in the Linux shape (0.27 s)
- [X] SCN-003-T05 [US1] `ShowSceneEditError`, `ShowStore.duplicateScene(_:newID:name:)` (read, `duplicated`, refuse an ID that has a file, atomic write; original file untouched) and `referencedMediaIDs()` (`StoredMediaReferences`) in Packages/ShowControl/Sources/ShowStorage/ShowStore.swift — Verified 2026-11-13: ShowSceneEditTests (duplicate, refusals, media); `swift test --package-path Packages/ShowControl` 25/25 on the host (0.19 s) and in the Linux shape (0.27 s)
- [X] SCN-003-T06 [P] [US1] Tests in Packages/ShowControl/Tests/ShowControlTests/ShowSceneEditTests.swift: acceptance (two files, distinct IDs, each loads with the other file deleted, equal `liveState`, original's cues still resolve after save and load); insert placement and position; missing scene and taken ID refused with nothing written; shared media: both scenes reference the same photo/video IDs, removing the original's cues removes only the original's file and `referencedMediaIDs` still lists the media — Verified 2026-11-13: ShowSceneEditTests 6/6 (0.03 s); `swift test --package-path Packages/ShowControl` 25/25 on the host (0.19 s) and in the Linux shape (0.27 s)
- [X] SCN-003-T07 [US1] `ShowCoordinator.duplicateScene(of:)` (check the 256-cue limit before any file is written; new ID injectable for tests; editor messages for refusals; save) and the scene-name cache in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift — Verified 2026-11-13: ShowSceneEditCoordinatorTests 3/3; xcodebuild test-without-building on the own iOS 27.2 simulator (SCN3 iPhone 17): projectM-iOSTests 327/327 (35.3 s)
- [X] SCN-003-T08 [US1] Duplicate Scene in the cue's context menu and as a VoiceOver action; "Scene: <name>" caption and ", scene <name>" value when the name differs from the label, in Apps/projectM-iOS/Views/ShowEditorView.swift — Verified 2026-11-13: SceneDuplicateUITests (swipe Duplicate, 'Scene: Build B' value) and ShowCueUITests unchanged; SceneDuplicateUITests 1/1 (23.4 s; 28.3 s in a fresh-build run) and ShowCueUITests 2/2 (11.8 s, 15.0 s)

## Phase 4: User Story 2 — Rename a scene (P1)

**Goal**: Rename Scene… changes the scene's name, never its ID or any cue.
**Independent test**: SCN-003-S2 in ShowSceneEditTests and ShowCoordinatorTests.

- [X] SCN-003-T09 [US2] `ShowStore.renameScene(_:to:)` (read, `renamed`, atomic rewrite of the same file; invalid name refused, file unchanged) in Packages/ShowControl/Sources/ShowStorage/ShowStore.swift, with tests in Packages/ShowControl/Tests/ShowControlTests/ShowSceneEditTests.swift (ID, file name and every cue reference unchanged; two cues sharing the scene both see the new name; labels unchanged; a missing scene is refused and nothing is written) — Verified 2026-11-13: ShowSceneEditTests.testRenameKeepsTheIDTheFileAndEveryCueReference, testRefusedRenamesLeaveTheFile; `swift test --package-path Packages/ShowControl` 25/25 on the host (0.19 s) and in the Linux shape (0.27 s)
- [X] SCN-003-T10 [US2] `ShowCoordinator.renameScene(of:to:)` and the Rename Scene… alert (`showSceneNameField`) in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift and Apps/projectM-iOS/Views/ShowEditorView.swift — Verified 2026-11-13: ShowSceneEditCoordinatorTests.testRenameSceneKeepsTheIDAndEveryCue; SceneDuplicateUITests rename via the alert
- [X] SCN-003-T11 [US1] [US2] Coordinator tests in Apps/projectM-iOS/Tests/ShowSceneEditCoordinatorTests.swift (a new file, keeping the shared ShowCoordinatorTests untouched): duplicate inserts after the source with a new ID and leaves the position and applied scene alone; stepping applies both scenes with distinct IDs; rename keeps the ID; refusals (missing scene, invalid name, full show with no scene file written) set the editor message — Verified 2026-11-13: ShowSceneEditCoordinatorTests 3/3 (0.04 s); xcodebuild test-without-building on the own iOS 27.2 simulator (SCN3 iPhone 17): projectM-iOSTests 327/327 (35.3 s)
- [X] SCN-003-T12 [US1] [US2] UI test in Apps/projectM-iOS/UITests/SceneDuplicateUITests.swift (`-uitestShowSeed`): Settings → Show, Duplicate Scene on cue 2, Rename Scene… "Build B", back; Next from cue 1 applies scene 2 then the copy (distinct ID, same visual) (S5, < 30 s) — Verified 2026-11-13: SceneDuplicateUITests 1/1 (23.4 s; 28.3 s in a fresh-build run) and ShowCueUITests 2/2 (11.8 s, 15.0 s); simulator only, never device evidence

## Phase 5: User Story 3 — Shared rule for later rows (P2)

- [X] SCN-003-T13 [US3] Amend ADR-0028 (duplicate/rename rule, kept-exactly definition, name trimming) and ADR-0033 (show actions, reference rules for cues, media and edges, FILE-010/FILE-011 obligations) in docs/adr/0028-scene-document-format.md and docs/adr/0033-show-cue-list-document.md — Verified 2026-11-13: ADR-0028 and ADR-0033 amendments; `python3 scripts/validate_docs.py` OK

## Phase 6: Polish

- [X] SCN-003-T14 Run `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, both packages on the host and in the Linux shape, the app tests and UI tests on the own simulator; count PosterBoard reports before and after; record pass counts and durations against the S6 budgets and the no-network check (SCN-003-R10) in spec.md's Status — Verified 2026-11-13: check_compliance OK, validate_docs OK (674 files); SceneFormat 48/48 and ShowControl 25/25 on the host and Linux shape; app runs above; PosterBoard reports 32 before and 32 after

## Analysis fixes (speckit-analyze, 2026-11-13)

- U1 (MEDIUM): the full-show refusal must write no scene file (spec Edge Cases) → T07 checks the limit first, T11 tests it.
- U2 (MEDIUM): Rename Scene on a missing scene (spec Edge Cases) had no test → T09.
- C1 (LOW): SCN-003-R10 (no network) and S6 (budgets) had no explicit task → T14.
- No constitution conflicts; coverage after fixes: R1-R10 and S1-S6 each map to at least one task.

## Dependencies

T01 → T06. T02 → T03, T05, T09. T04, T05 → T07 → T08. T09 → T10. T07, T10 → T11, T12. T13 and T14 last.
US1 and US2 share the store file and the editor; do them in order.

## Parallel examples

T03 alongside T04 (different packages); T06 alongside T07 (package tests vs app code); T13 alongside T12.

## Implementation strategy

MVP = Phase 2 + US1 (the row's acceptance). US2 completes the row; US3 is documentation.
