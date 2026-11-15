# Tasks: UIX-008 Multiwindow Document Editing

**Input**: design documents in `specs/294-uix-008-multiwindow-document-editing/` (spec, plan, research, data-model,
contracts/scene-editor-windows.md, quickstart)

**Tests**: requested by the brief and the spec (UIX-008-S1-S6). Budgets (owner rule 7): unit test about 1-2 s, at
most 10 s; UI test under 30 s; any xcodebuild run under 10 minutes.

Format: `- [ ] UIX-008-Txx [P?] [Story?] Description with file path`. `{device}` marks a task the Mac cannot
finish. Logs go to `.autonomous/logs-uix-008/`.

## Phase 1: Setup

- [X] UIX-008-T01 Audit: confirm one `WindowGroup`, `UIApplicationSupportsMultipleScenes` false, one
  `AppCoordinator` creating the only `CaptureManager` and renderer, scenes stored by `ShowStore`; record it in
  spec.md's baseline. — Verified 2026-11-15: audit in spec.md's baseline (grep of ProjectMApp.swift, project.yml, AppCoordinator `CaptureManager(` and `prepareRenderer`, ShowStore).
- [X] UIX-008-T02 Set `UIApplicationSupportsMultipleScenes: true` in `project.yml` (the external display role
  configuration unchanged; comment cites ADR-0105) and run `xcodegen generate`. — Verified 2026-11-15: project.yml, `xcodegen generate`; the built Info.plist has `UIApplicationSupportsMultipleScenes` true and the external display role unchanged; ExternalDisplayUITests 3/3 pass on the UIX8 iPhone 17 simulator.

## Phase 2: Foundational

- [X] UIX-008-T03 Create `Apps/projectM-iOS/Coordinators/SceneEditorWindowRouter.swift`: `SceneEditorWindowID`
  (Codable, Hashable, `sceneID`), `EngineInstanceLedger` (`coordinators`, `renderers`), `PerformanceWindowClaim`
  (`claim`, `release`, `isPerformer`), `SceneEditorWindowRouter` (`request` → `.openNew`/`.focusExisting`,
  `editor(for:window:)` one editor per scene, `release(window:)`). — Verified 2026-11-15: SceneEditorWindowRouterTests 3/3 (0.010 s) on the UIX8 iPad Pro iOS 27.2 simulator.
- [X] UIX-008-T04 Count `AppCoordinator` initializations and renderer creations in
  `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (two lines) and add the `sceneEditors` router and
  `performanceWindows` claim properties. — Verified 2026-11-15: SceneEditorWindowRouterTests.testEditorWindowsCreateNoEngineOrCapture; build with the type-check flags shows no warning in the touched files.
- [X] UIX-008-T05 Create `Apps/projectM-iOS/Coordinators/ShowCoordinator+SceneEditing.swift`: `editableScene(_:)`
  (document plus the file's bytes; nil when not in the library or unreadable), `storedSceneBytes(_:)`,
  `saveEditedScene(_:expectedBytes:replacing:)` per contract W4 (lock, missing, conflict, `ShowStore.saveScene`,
  `sceneNames`, `sceneFilesChanged`; never applies). — Verified 2026-11-15: SceneDocumentEditorTests 6/6 (lock, conflict, missing, separate files).

## Phase 3: User Story 1 - Edit two saved scenes side by side (P1)

**Independent test**: two editors over two library scenes edit, undo and save independently (UIX-008-S1, S2).

- [X] UIX-008-T06 [US1] Create `Apps/projectM-iOS/Coordinators/SceneDocumentEditor.swift` per data-model.md:
  `rename` (SCN-003 rules, key `name`), `setOpacity(_:ofLayer:)` ("clamped to 0…1", key `opacity.<instance>`),
  own `SceneHistory<SceneDocument>` (standard limits), `undo`/`redo`, `isDirty`, `save`/`replace`/`reload`. — Verified 2026-11-15: SceneDocumentEditorTests 6/6 (0.039 s).
- [X] UIX-008-T07 [US1] Tests `Apps/projectM-iOS/Tests/SceneDocumentEditorTests.swift`: two editors on two
  scenes (edits isolated, undo isolated, two files equal each editor's bytes, `sceneNames` lists both), lock
  refusal, conflict then replace and reload, missing scene, and UIX-008-R12: the stored file (what the main
  window reads) is unchanged by unsaved edits. — Verified 2026-11-15: SceneDocumentEditorTests 6/6 (0.039 s), including testTwoScenesEditIndependentlyAndSaveToSeparateFiles.
- [X] UIX-008-T08 [US1] Create `Apps/projectM-iOS/Views/SceneEditorWindowView.swift` per contract W3 (preview,
  name field, ACC-005 opacity sliders, Undo/Redo/Save with keyboard shortcuts, dirty marker, conflict alert, W6
  DEBUG probe); every control has a VoiceOver label and value and scales with Dynamic Type (UIX-008-R11, FR-070);
  body split into small properties. — Verified 2026-11-15: SceneEditorWindowUITests 1/1 (26.8 s) finds the name field, ACC-005 slider, dirty marker and probe; no type-check warning.
- [X] UIX-008-T09 [US1] Add the editor `WindowGroup(for: SceneEditorWindowID.self)` to
  `Apps/projectM-iOS/ProjectMApp.swift` and "Open in New Window" (`sceneFolderOpenWindow`, gated on
  `supportsMultipleWindows`) to `Apps/projectM-iOS/Views/SceneFoldersView.swift`. — Verified 2026-11-15: SceneEditorWindowUITests opens the window from Scene Folders' swipe action on the iPad simulator; on the iPhone simulator the test skips (action not offered).

## Phase 4: User Story 2 - One window per scene, one live output (P1)

**Independent test**: routing and instance counts (UIX-008-S3, S4).

- [X] UIX-008-T10 [US2] Create `Apps/projectM-iOS/Views/PerformanceWindowGate.swift` (claim on appear, release
  on disappear, notice for non-performers, the performing window's own scene phase to `sceneBecame`) and wrap the
  main window group's content in it in `ProjectMApp.swift`. — Verified 2026-11-15: SceneEditorWindowRouterTests.testOneMainWindowPerformsAndTheNextTakesOver; all UI tests above launch into the performing main window.
- [X] UIX-008-T11 [US2] Tests `Apps/projectM-iOS/Tests/SceneEditorWindowRouterTests.swift`: same scene twice →
  `.focusExisting` and no second editor, release frees it, performance claim hand-over, ledger unchanged after
  creating router, editors and a save. — Verified 2026-11-15: SceneEditorWindowRouterTests 3/3.

## Phase 5: User Story 3 - Safe saving (P2)

- [X] UIX-008-T12 [US3] Verify the safe-saving paths (UIX-008-R9, Story 3) through T07's lock, conflict and missing
  tests and the dirty marker clearing after Save in T13's UI test. — Verified 2026-11-15: SceneDocumentEditorTests lock/conflict/missing tests and the dirty marker clearing after Save in SceneEditorWindowUITests.

## Phase 6: Polish and verification

- [X] UIX-008-T13 UI test `Apps/projectM-iOS/UITests/SceneEditorWindowUITests.swift` on "UIX8 iPad Pro": Scene
  Folders → Open in New Window → rename and change an opacity → Save → the file probe shows both (under 30 s). — Verified 2026-11-15: SceneEditorWindowUITests 1/1 on UIX8 iPad Pro iOS 27.2 (24.1-28.4 s over four runs, including a run that first closed a restored editor window).
- [X] UIX-008-T14 Regression: OUT-001 external display UI tests and `SceneFoldersUITests` on the iPad simulator;
  `LibraryBackupAppTests`, `SettingsTests`; type-check budget flags; repo checks; privacy manifest and network
  symbol checks on the Debug app. — Verified 2026-11-15: ExternalDisplayUITests 3/3 on the iPhone simulator; on the iPad simulator testTheResolutionSettingChangesTheExternalDrawable fails the same way on the base commit (pre-existing, not UIX-008); SceneFoldersUITests 1/1; LibraryBackupAppTests, SettingsTests, SceneFolderAcceptanceTests, SceneHistoryCoordinatorTests pass (33 tests); repo checks OK; test_scripts 186 OK; check_privacy_manifest OK; check_network_symbols OK.
- [X] UIX-008-T15 Write `docs/adr/0105-multiwindow-scene-editor.md` and update spec status. — Verified 2026-11-15: docs/adr/0105-multiwindow-scene-editor.md, ADR index, ADR-0023 amendment note; validate_docs OK.
- [ ] UIX-008-T16 {device} D2 (iPadOS 27.2) and D3 (iPadOS 26.5) with Stage Manager: two editor windows beside the
  main window; edit and save each; the live output never changes; the external display still follows the main
  window.

## Dependencies

T01-T02 → T03-T05 → US1 (T06-T09) → US2 (T10-T11) → T12-T15; T16 last.
Parallel: T07 with T08; T10 with T11.

## Implementation strategy

MVP is US1 through the model and app tests (the roadmap acceptance); windows and gate next; the UI test last.
