# Tasks: SCN-015 Scene Lock Mode

**Input**: [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md), [contracts/scene-lock.md](contracts/scene-lock.md)
**Tests**: requested by the roadmap acceptance and the brief (acceptance through coordinator APIs, persistence, UI test under 30 s).

## Phase 1: Foundational (the lock model)

- [ ] SCN-015-T01 `SceneLock` (key `settings.scene.locked`, absent → false; `lock()`, `unlock()`, `refusesEdit()`, refusal message "Scene locked. Unlock the scene to edit.", announcements "Scene locked"/"Scene unlocked") in Apps/projectM-iOS/Coordinators/SceneLock.swift; `AppSettings.sceneLock` and the key in `AppSettings.allKeys` (UI-test reset) in Apps/projectM-iOS/Coordinators/AppSettings.swift
- [ ] SCN-015-T02 [P] Key lists: `excludedKeys` in Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift and `ALLOWED_KEYS` in scripts/run_device_tests.py

## Phase 2: User Story 1 — Lock refuses edits (P1)

- [ ] SCN-015-T03 [US1] Guards (contract L2): `ParameterInspectorTargets.target(for:settings:)` in Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift; `MacroCoordinator.setValue` in Apps/projectM-iOS/Coordinators/MacroCoordinator.swift; snapshot save/rename/delete/recall in Apps/projectM-iOS/Coordinators/SceneSnapshotCoordinator.swift (wired in AppCoordinator+SceneSnapshots.swift); undo/redo and canUndo/canRedo in Apps/projectM-iOS/Coordinators/SceneHistoryCoordinator.swift
- [ ] SCN-015-T04 [US1] Show guards (every edit method; refusal into `editorMessage` and the library lane) in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift; wiring of `sceneLock` into show and history and the announcer in Apps/projectM-iOS/Coordinators/AppCoordinator.swift
- [ ] SCN-015-T05 [US1] UI: Settings "Scene lock" section and disabled scene sections (Apps/projectM-iOS/Views/SettingsView.swift, Apps/projectM-iOS/Views/SceneLockViews.swift); show editor without Edit, add buttons, swipe-to-delete, drag reorder and edit menu items (Apps/projectM-iOS/Views/ShowEditorView.swift); shelf strip disabled (Apps/projectM-iOS/Views/ControlsOverlay.swift)

## Phase 3: User Story 2 — Perform while locked (P1)

- [ ] SCN-015-T06 [US2] Lock button `lockScene` in the controls (Apps/projectM-iOS/Views/ControlsOverlay.swift) and the "Scene locked" badge in the visualizer's top status stack (Apps/projectM-iOS/Views/VisualizerView.swift, SceneLockViews.swift); navigation paths untouched

## Phase 4: User Story 3 — Unlock deliberately (P1)

- [ ] SCN-015-T07 [US3] Unlock confirmation ("Unlock scene?" Unlock / Cancel) from the controls and Settings; VoiceOver value and named action; announcements in Apps/projectM-iOS/Views/SceneLockViews.swift

## Phase 5: Tests

- [ ] SCN-015-T08 [US1] [US2] [US3] Acceptance tests in Apps/projectM-iOS/Tests/SceneLockAcceptanceTests.swift: lock; inspector write, macro move, snapshot recall, cue delete, cue reorder, transition edit, undo all refused with scene document (autosave bytes), show file and settings byte-identical; Next/Previous/Go apply scenes; blackout and tap tempo work; unlock, edits work; persistence across a new `AppSettings`
- [ ] SCN-015-T09 [US1] [US2] [US3] UI test under 30 s in Apps/projectM-iOS/UITests/SceneLockUITests.swift: lock, swipe-delete on a cue leaves it, Next advances the cue, unlock with confirmation

## Phase 6: Polish

- [ ] SCN-015-T10 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, Xcode 26 type-check budget, regression of touched suites (snapshots, macros, show, history, inspector, shelf, LibraryBackup package), PosterBoard counts; record results in spec.md Status

## Dependencies

T01 → T02, T03, T04 → T05, T06, T07 → T08, T09 → T10.

## Implementation strategy

The model and coordinator guards first (they carry the acceptance), then UI, then tests.
