# Tasks: SCN-009 Scene A/B Compare

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/scene-compare.md](contracts/scene-compare.md)
**Tests**: requested by the roadmap acceptance and the brief (acceptance with real stores in a temporary folder, UI test under 30 s).

## Phase 1: Foundational (suspend and resume)

- [X] SCN-009-T01 Autosave `suspend()`, `isSuspended`, `resume(from:)` (contract C2; research SCN-009-D1, D2): while suspended `inputsChanged` only re-arms observation, `catchUp`, `commitNow`, `tick`, background and `flushSynchronously` write nothing and note no edit; resume re-arms against the given inputs and notes one edit only when the live inputs differ, in Apps/projectM-iOS/Coordinators/SceneAutosaveCoordinator.swift — Verified 2026-11-14: `SceneCompareAcceptanceTests` (every trigger fired while comparing: write counter and file bytes unchanged; resume notes one edit only when inputs differ); SceneAutosaveCoordinatorTests 4 pass
- [X] SCN-009-T02 [P] History `suspend()`, `isSuspended`, `resume()`, `onRestartWhileSuspended` (contract C3; D7): capture and recordStep record nothing, undo/redo do nothing, canUndo/canRedo false; `restart()` while suspended calls the hook first, in Apps/projectM-iOS/Coordinators/SceneHistoryCoordinator.swift — Verified 2026-11-14: `testTwentySwitches…` (undo refused, canUndo false, undo stack unchanged) and `testCurrentSceneSideAndRestartAbandons` (restart ends Compare); SceneHistoryCoordinatorTests 4 pass
- [X] SCN-009-T03 [P] Snapshot edits refused with "Finish Compare first." while `isComparing()` (contract C4) and a weak `compare` link for the views, in Apps/projectM-iOS/Coordinators/SceneSnapshotCoordinator.swift — Verified 2026-11-14: `testTwentySwitches…` (save false, recall returns "Finish Compare first."); SceneSnapshotAcceptanceTests 3 and SceneLockAcceptanceTests 3 pass

## Phase 2: User Story 1 — Switch between two looks (P1)

- [X] SCN-009-T04 [US1] `SceneCompareCoordinator` with `SceneCompareChoice`, `SceneCompareSide`, `SceneCompareSession` (data-model.md; "`b` is always a snapshot; `a != b`"): `start(a:b:)` (lock refusal; flush, endCoalescing, capture baseline, suspend both, apply A, announce, `onStarted`), side values = baseline overlaid with `SceneSnapshotRecallPlan.writes` (D4), `show(_:)`/`toggle()` writing only differing values (D3, D6) in Apps/projectM-iOS/Coordinators/SceneCompareCoordinator.swift — Verified 2026-11-14: `testTwentySwitches…` (A shown at start, each switch live right after `toggle()`), SceneCompareAcceptanceTests 4 pass
- [X] SCN-009-T05 [US1] Wiring shared by app and tests (`connect(snapshots:autosave:history:lock:inputs:restore:announce:)`), `AppCoordinator.sceneCompare` and one connect call closing Settings on start, in Apps/projectM-iOS/Coordinators/AppCoordinator+SceneCompare.swift and Apps/projectM-iOS/Coordinators/AppCoordinator.swift — Verified 2026-11-14: app builds; `SceneCompareUITests` (Start Compare closes Settings, the bar appears)
- [X] SCN-009-T06 [US1] UI: "Compare A/B…" row (`sceneCompareOpen`, disabled without a usable snapshot) and setup sheet (`sceneCompareA`, `sceneCompareB`, `sceneCompareStart`) in Apps/projectM-iOS/Views/SceneCompareViews.swift and Apps/projectM-iOS/Views/SceneSnapshotRows.swift; "Comparing A/B" bar (`sceneCompareBar` value "A, <name>"/"B, <name>", side buttons `sceneCompareSideA`/`sceneCompareSideB`, `sceneCompareDone`) in the top status stack of Apps/projectM-iOS/Views/VisualizerView.swift — Verified 2026-11-14: `SceneCompareUITests` (Compare row, sheet, bar value "A, Current scene" / "B, Snapshot 1")

## Phase 3: User Story 2 — Keep or cancel (P1)

- [X] SCN-009-T07 [US2] `keep(_:)` (lock refusal; show side, resume, `commitNow`, `recordStep("Keep <name>")`, announce "Kept <name>"), `cancel()` (history `apply` of the baseline then differing values, resume, "Compare cancelled"), `abandon()` ("Compare ended") in Apps/projectM-iOS/Coordinators/SceneCompareCoordinator.swift; Done's in-place finish row (`sceneCompareKeepA`, `sceneCompareKeepB`, `sceneCompareCancel`; Back keeps comparing) in Apps/projectM-iOS/Views/SceneCompareViews.swift — Verified 2026-11-14: `testKeepBWritesOnceWithOneUndoStep`, `testTwentySwitches…` (Cancel), `testCurrentSceneSideAndRestartAbandons` (abandon); `SceneCompareUITests` (Done › Keep B, "Kept Snapshot 1" announced)

## Phase 4: User Story 3 — Compare against the current scene (P2)

- [X] SCN-009-T08 [US3] `.current` as side A ("Current scene"; start changes nothing; Keep A writes nothing and records no step) in Apps/projectM-iOS/Coordinators/SceneCompareCoordinator.swift and the sheet's A picker in Apps/projectM-iOS/Views/SceneCompareViews.swift — Verified 2026-11-14: `testCurrentSceneSideAndRestartAbandons` (A = Current scene changes nothing; Keep A writes nothing, no undo step); `SceneCompareUITests` uses Current scene as A

## Phase 5: Tests

- [X] SCN-009-T09 [US1] [US2] [US3] Acceptance tests in Apps/projectM-iOS/Tests/SceneCompareAcceptanceTests.swift: 20 toggles leave `current.scene`, `current.scene.bak`, snapshot entries and undo stack unchanged even with Settings closing, terminate flush and the debounce tick; Cancel restores; Keep B writes once with one undo step "Keep S2"; lock refuses start and Keep, Cancel works; a fresh coordinator on the folder during Compare restores the pre-Compare scene; Current-scene side; cue restart abandons; a switch's values are live right after `show(_:)` returns (S5); undo/redo and snapshot save/recall are refused during Compare (R4) — Verified 2026-11-14: SceneCompareAcceptanceTests 4 pass (0.04 s each) on "SCN9 iPhone 17" (iOS 27.2)
- [X] SCN-009-T10 [US1] [US2] UI test under 30 s in Apps/projectM-iOS/UITests/SceneCompareUITests.swift: save two snapshots, start Compare, switch A/B, Keep A, the intensity slider shows A's value — Verified 2026-11-14: SceneCompareUITests passes in 26.8 s, 30.1 s and 34.4 s on "SCN9 iPhone 17" (iOS 27.2) on a loaded Mac (other agents building); the pre-existing SceneSnapshotUITests took 52-57 s on the same runs

## Phase 6: Polish

- [X] SCN-009-T11 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), type-check budget, `LibraryBackupAppTests` (no new keys), privacy manifest and network symbol checks on the Debug app; spec status — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 164 OK; type-check flags show no warning in SCN-009 files; LibraryBackupAppTests pass (no new keys); check_privacy_manifest OK and check_network_symbols OK on the Debug app

## Dependencies

T01-T03 → T04 → T05 → T06, T07, T08 → T09, T10 → T11. T02 and T03 are parallel with T01.

## Implementation Strategy

MVP is US1 plus US2 (both P1: the switch is useless without Keep/Cancel); US3 is a small extension of the same coordinator.
