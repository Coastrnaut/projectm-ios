# Tasks: SCN-003 Scene Duplicate and Rename

**Input**: Design documents from `specs/074-scn-003-scene-duplicate-and-rename/` (spec, plan, research,
data-model, contracts/scene-duplicate-rename.md, quickstart)

**Tests**: requested by the spec (SCN-003-S1 to S6) and the roadmap row ("schema round trip +
integration + simulator"). Budgets (owner rule 7): unit ≤ 10 s, suite < 1 min, UI test < 30 s,
property test ≤ 1 s.

A task is ticked `[X]` only when verified, with " — Verified <date>: <how>".

## Phase 1: Setup

- [ ] SCN-003-T01 Add ParameterGraph as a test dependency of ShowControlTests (registry for `liveState`) in Packages/ShowControl/Package.swift

## Phase 2: Foundational (scene-level rule, blocks every story)

- [ ] SCN-003-T02 Implement `SceneEditError`, `SceneDocument.isValidName`, `normalizedName` (trim; "1…120 characters", no control characters), `copyName` ("<name> copy" within 120), `renamed(to:)` and `duplicated(newID:name:)` (canonical uppercase UUID, ≠ original) in Packages/SceneFormat/Sources/SceneFormat/SceneEditing.swift; make the validator's name check call `isValidName` in Packages/SceneFormat/Sources/SceneFormat/SceneValidation.swift
- [ ] SCN-003-T03 [P] Tests in Packages/SceneFormat/Tests/SceneFormatTests/SceneEditingTests.swift: name table (valid, trimmed, empty, spaces only, 120 and 121 characters, emoji graphemes, tab, newline inside, NUL, DEL) (S4); copyName shortening; duplicate of the all-kinds fixture: distinct IDs, both decode from their own bytes, `liveState` equal, bytes equal after putting the ID and name back (S1 at the scene level); rename keeps the ID (S2); invalid and same IDs refused; fixed-seed property test over 200 generated scenes (S3, ≤ 1 s)

## Phase 3: User Story 1 — Duplicate a cue's scene (P1)

**Goal**: Duplicate Scene in Settings → Show stores a copy under a new ID and inserts its cue after the source cue.
**Independent test**: SCN-003-S1 in ShowSceneEditTests; app path in ShowCoordinatorTests.

- [ ] SCN-003-T04 [US1] `ShowCueList.insert(sceneID:label:after:cueID:)` (position unchanged; errors as `append` plus `unknownCue`) and `copyLabel` ("<label> copy" within 80) in Packages/ShowControl/Sources/ShowControl/ShowCueList.swift
- [ ] SCN-003-T05 [US1] `ShowSceneEditError`, `ShowStore.duplicateScene(_:newID:name:)` (read, `duplicated`, refuse an ID that has a file, atomic write; original file untouched) and `referencedMediaIDs()` (`StoredMediaReferences`) in Packages/ShowControl/Sources/ShowStorage/ShowStore.swift
- [ ] SCN-003-T06 [P] [US1] Tests in Packages/ShowControl/Tests/ShowControlTests/ShowSceneEditTests.swift: acceptance (two files, distinct IDs, each loads with the other file deleted, equal `liveState`, original's cues still resolve after save and load); insert placement and position; missing scene and taken ID refused with nothing written; shared media: both scenes reference the same photo/video IDs, removing the original's cues removes only the original's file and `referencedMediaIDs` still lists the media
- [ ] SCN-003-T07 [US1] `ShowCoordinator.duplicateScene(of:)` (new ID injectable for tests, editor messages for refusals, save) and the scene-name cache in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift
- [ ] SCN-003-T08 [US1] Duplicate Scene in the cue's context menu and as a VoiceOver action; "Scene: <name>" caption and ", scene <name>" value when the name differs from the label, in Apps/projectM-iOS/Views/ShowEditorView.swift

## Phase 4: User Story 2 — Rename a scene (P1)

**Goal**: Rename Scene… changes the scene's name, never its ID or any cue.
**Independent test**: SCN-003-S2 in ShowSceneEditTests and ShowCoordinatorTests.

- [ ] SCN-003-T09 [US2] `ShowStore.renameScene(_:to:)` (read, `renamed`, atomic rewrite of the same file; invalid name refused, file unchanged) in Packages/ShowControl/Sources/ShowStorage/ShowStore.swift, with tests in Packages/ShowControl/Tests/ShowControlTests/ShowSceneEditTests.swift (ID, file name and every cue reference unchanged; two cues sharing the scene both see the new name; labels unchanged)
- [ ] SCN-003-T10 [US2] `ShowCoordinator.renameScene(of:to:)` and the Rename Scene… alert (`showSceneNameField`) in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift and Apps/projectM-iOS/Views/ShowEditorView.swift
- [ ] SCN-003-T11 [US1] [US2] Coordinator tests in Apps/projectM-iOS/Tests/ShowCoordinatorTests.swift: duplicate inserts after the source with a new ID and leaves the position and applied scene alone; stepping applies both scenes with distinct IDs; rename keeps the ID; refusals set the editor message
- [ ] SCN-003-T12 [US1] [US2] UI test in Apps/projectM-iOS/UITests/SceneDuplicateUITests.swift (`-uitestShowSeed`): Settings → Show, Duplicate Scene on cue 2, Rename Scene… "Build B", back; Next from cue 1 applies scene 2 then the copy (distinct ID, same visual) (S5, < 30 s)

## Phase 5: User Story 3 — Shared rule for later rows (P2)

- [ ] SCN-003-T13 [US3] Amend ADR-0028 (duplicate/rename rule, kept-exactly definition, name trimming) and ADR-0033 (show actions, reference rules for cues, media and edges, FILE-010/FILE-011 obligations) in docs/adr/0028-scene-document-format.md and docs/adr/0033-show-cue-list-document.md

## Phase 6: Polish

- [ ] SCN-003-T14 Run `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, both packages on the host and in the Linux shape, the app tests and UI tests on the own simulator; count PosterBoard reports before and after; record results in spec.md's Status

## Dependencies

T01 → T06. T02 → T03, T05, T09. T04, T05 → T07 → T08. T09 → T10. T07, T10 → T11, T12. T13 and T14 last.
US1 and US2 share the store file and the editor; do them in order.

## Parallel examples

T03 alongside T04 (different packages); T06 alongside T07 (package tests vs app code); T13 alongside T12.

## Implementation strategy

MVP = Phase 2 + US1 (the row's acceptance). US2 completes the row; US3 is documentation.
