# Tasks: SCN-015 Scene Lock Mode

**Input**: [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md), [contracts/scene-lock.md](contracts/scene-lock.md)
**Tests**: requested by the roadmap acceptance and the brief (acceptance through coordinator APIs, persistence, UI test under 30 s).

## Phase 1: Foundational (the lock model)

- [X] SCN-015-T01 `SceneLock` (key `settings.scene.locked`, absent → false; `lock()`, `unlock()`, `refusesEdit()`, refusal message "Scene locked. Unlock the scene to edit.", announcements "Scene locked"/"Scene unlocked") in Apps/projectM-iOS/Coordinators/SceneLock.swift; `AppSettings.sceneLock` and the key in `AppSettings.allKeys` (UI-test reset) in Apps/projectM-iOS/Coordinators/AppSettings.swift — Verified 2026-11-14: `SceneLockAcceptanceTests.testTheLockPersistsAndIsListedWithTheSettingsKeys` and `SettingsTests.testOnlyTheSettingsKeysAreWritten` pass on "SCN15 iPhone 17" (iOS 27.2)
- [X] SCN-015-T02 [P] Key lists: `excludedKeys` in Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift and `ALLOWED_KEYS` in scripts/run_device_tests.py — Verified 2026-11-14: `swift test --package-path Packages/LibraryBackup` 77 pass (15.8 s; `settings.scene.locked` also erased with Settings via `LibraryErasePolicy`); `test_scripts.py` 159 OK

## Phase 2: User Story 1 — Lock refuses edits (P1)

- [X] SCN-015-T03 [US1] Guards (contract L2): `ParameterInspectorTargets.target(for:settings:)` in Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift; `MacroCoordinator.setValue` in Apps/projectM-iOS/Coordinators/MacroCoordinator.swift; snapshot save/rename/delete/recall in Apps/projectM-iOS/Coordinators/SceneSnapshotCoordinator.swift (wired in AppCoordinator+SceneSnapshots.swift); undo/redo and canUndo/canRedo in Apps/projectM-iOS/Coordinators/SceneHistoryCoordinator.swift — Verified 2026-11-14: `testLockedSceneIgnoresEditsButPermitsCueNavigation` (inspector target, macro, snapshot recall/save, undo/redo refused; 13 refusals counted)
- [X] SCN-015-T04 [US1] Show guards (every edit method; refusal into `editorMessage` and the library lane) in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift; wiring of `sceneLock` into show and history and the announcer in Apps/projectM-iOS/Coordinators/AppCoordinator.swift — Verified 2026-11-14: same test (cue delete, reorder, transition, rename, duplicate, folder, tag refused; editor message set); ScenePackAcceptanceTests, SceneFolderAcceptanceTests, SceneTagAcceptanceTests, ShowCoordinatorTests still pass
- [X] SCN-015-T05 [US1] UI: Settings "Scene lock" section and disabled scene sections (Apps/projectM-iOS/Views/SettingsView.swift, Apps/projectM-iOS/Views/SceneLockViews.swift); show editor without Edit, add buttons, swipe-to-delete, drag reorder, edit menu items and the edit VoiceOver actions (Rename, Duplicate Scene, Rename Scene, Transition, Move Up, Move Down; Go to Cue and Assign MIDI stay) plus a "Scene locked" note (Apps/projectM-iOS/Views/ShowEditorView.swift); shelf strip disabled (Apps/projectM-iOS/Views/ControlsOverlay.swift) — Verified 2026-11-14: `SceneLockUITests` (no Delete on swipe, Add Current Scene disabled, "Scene locked" note); SceneUndoUITests and SceneSnapshotUITests still pass

## Phase 3: User Story 2 — Perform while locked (P1)

- [X] SCN-015-T06 [US2] Lock button `lockScene` in the controls (Apps/projectM-iOS/Views/ControlsOverlay.swift) and the "Scene locked" badge in the visualizer's top status stack (Apps/projectM-iOS/Views/VisualizerView.swift, SceneLockViews.swift); navigation paths untouched — Verified 2026-11-14: `SceneLockUITests` (Lock scene shows the badge, Next advances to "Cue 2 of 5, Build" while locked); ShowCueUITests still pass

## Phase 4: User Story 3 — Unlock deliberately (P1)

- [X] SCN-015-T07 [US3] Unlock confirmation ("Unlock scene?" Unlock / Cancel) from the controls and Settings; VoiceOver value and named action; announcements in Apps/projectM-iOS/Views/SceneLockViews.swift — Verified 2026-11-14: `SceneLockUITests` (Unlock asks first, the badge stays until Unlock); `testUnlockingAllowsEditsAgain` ("Scene unlocked" announced)

## Phase 5: Tests

- [X] SCN-015-T08 [US1] [US2] [US3] Acceptance tests in Apps/projectM-iOS/Tests/SceneLockAcceptanceTests.swift: lock; inspector write, macro move, snapshot recall, cue delete, cue reorder, transition edit, undo all refused with scene document (autosave bytes), show file and settings byte-identical; Next/Previous/Go apply scenes; blackout and tap tempo work; unlock, edits work; persistence across a new `AppSettings` — Verified 2026-11-14: SceneLockAcceptanceTests 3 pass (0.07 s total); regression set 77 unit tests pass (1.3 s)
- [X] SCN-015-T09 [US1] [US2] [US3] UI test under 30 s in Apps/projectM-iOS/UITests/SceneLockUITests.swift: lock, swipe-delete on a cue leaves it, Next advances the cue, unlock with confirmation — Verified 2026-11-14: SceneLockUITests passes in 15.1 s and 14.4 s

## Phase 6: Polish

- [X] SCN-015-T10 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, Xcode 26 type-check budget, regression of touched suites (snapshots, macros, show, history, inspector, shelf, LibraryBackup package), PosterBoard counts; record results in spec.md Status — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 OK (27.5 s); check_privacy_manifest and check_network_symbols OK on the Debug simulator app; no type-check warning over 150 ms in changed lines (three 198-212 ms warnings sit on untouched lines: ControlsOverlay.swift:75, SceneHistoryControls.swift:36, VisualizerView.swift:61); PosterBoard reports 25 before and 25 after

## Dependencies

T01 → T02, T03, T04 → T05, T06, T07 → T08, T09 → T10.

## Implementation strategy

The model and coordinator guards first (they carry the acceptance), then UI, then tests.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1 → T01, T08; R2 → T06, T07, T09; R3, R4 → T03, T04, T08; R5 → T06 (navigation untouched), T08, T09;
R6 → T05, T09; R7 → T06; R8 → T07; R9 → T01, T02; R10 → T10. S1-S4 → T08; S5 → T09. Findings applied:
(1) the show editor's VoiceOver edit actions (Move Up/Down, Rename…) were not named by any task, so a VoiceOver
user could still reorder through the UI path (the coordinator would refuse, but the UI would offer it); T05 now
gates them. (2) "byte-identical settings" was undefined; the spec's S1 now says which values are compared.
Noted, not tasked: MOD-012's matrix is not in this tree; its coordinator needs the same guard when it merges.
No constitution conflicts, no unmapped tasks.
