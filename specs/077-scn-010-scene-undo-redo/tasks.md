# Tasks: SCN-010 Scene Undo and Redo

**Input**: Design documents from `specs/077-scn-010-scene-undo-redo/` (spec, plan, research,
data-model, contracts/scene-history.md, quickstart)

**Tests**: requested by the spec (SCN-010-S1 to S6) and the roadmap row ("schema round trip +
integration + simulator"). Budgets (owner rule 7): unit ≤ 10 s, suite < 1 min, UI test < 30 s,
property test ≤ 1 s.

A task is ticked `[X]` only when verified, with " — Verified <date>: <how>".

## Phase 1: Setup

- [ ] SCN-010-T01 Confirm the worktree builds: `git submodule update --init --depth 1 Vendor/presets/*`, `xcodegen generate`, own simulator "SCN10 iPhone 17" (iOS 27.2); count PosterBoard reports before

## Phase 2: Foundational (the history model, blocks every story)

- [ ] SCN-010-T02 Implement `SceneHistoryLimits`, `SceneHistoryState` (+ `init(_ document:)`), `SceneHistoryStep`, `SceneHistoryRecord` and `SceneHistory` (record with no-op suppression and key coalescing, endCoalescing, undo, redo, reset, limits with eviction) in Packages/SceneFormat/Sources/SceneFormat/SceneHistory.swift (contract H1)
- [ ] SCN-010-T03 [P] Tests in Packages/SceneFormat/Tests/SceneFormatTests/SceneHistoryTests.swift: acceptance over SceneDocuments (visual/layer change, bars, glow intensity, text asset, orientation; undo all matches each recorded state's bytes in reverse, layer order and parameters included; redo all back to the final) (S1); new edit clears redo, no-op suppression, coalescing and drag-back-to-start, boundaries (S2); 200 edits → ≤ 50 steps, byte budget eviction (oldest undo, then farthest redo), oversize current (S3); fixed-seed property test against a reference model (S4, ≤ 1 s); host and Linux shape

## Phase 3: User Story 1 + 2 — Undo and redo look changes (P1)

**Goal**: Settings edits are recorded and undone/redone through the Settings path without restarting the source.
**Independent test**: SceneHistoryCoordinatorTests; SceneUndoUITests.

- [ ] SCN-010-T04 [US1] `SceneHistoryEdit.describe(from:to:)` (label and coalescing key per research D3/D7) and `SceneHistoryCoordinator` (observe inputs, capture bytes over a carry snapshot, record, undo, redo, endCoalescing, restart; photo/video change that alters the scene restarts) in Apps/projectM-iOS/Coordinators/SceneHistoryCoordinator.swift
- [ ] SCN-010-T05 [US1] Wiring in Apps/projectM-iOS/Coordinators/AppCoordinator+SceneHistory.swift (`applySceneInputs`, `undoSceneEdit`, `redoSceneEdit`), Apps/projectM-iOS/Coordinators/AppCoordinator.swift (create and start after the restore; restart on Reopen and Start fresh; end coalescing when Settings closes), Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift (restart after a cue applies) and Apps/projectM-iOS/Coordinators/SceneAutosaveCoordinator.swift (`carrySnapshot`) (R7-R9)
- [ ] SCN-010-T06 [US1] [US2] App tests in Apps/projectM-iOS/Tests/SceneHistoryCoordinatorTests.swift: scripted edits through a fake world → undo all/redo all match recorded bytes; labels and keys; slider coalescing ends at `endCoalescing`; photo replacement and `restart` empty both lists; applying a state is not recorded (S1, S2)

## Phase 4: User Story 3 — Know what will be undone (P2)

- [ ] SCN-010-T07 [US3] Settings toolbar Undo/Redo (`sceneUndo`, `sceneRedo`, "Undo <label>", disabled when empty, ⌘Z / ⇧⌘Z) and slider drag end → `endCoalescing` in Apps/projectM-iOS/Views/SettingsView.swift; hidden ⌘Z / ⇧⌘Z on the visualizer and the history passed to Settings in Apps/projectM-iOS/Views/VisualizerView.swift (R10)
- [ ] SCN-010-T08 [US1] [US2] [US3] UI test Apps/projectM-iOS/UITests/SceneUndoUITests.swift: Circular Spectrum, 16 bars, glow intensity slider; Undo label "Undo Glow Intensity …"; Undo twice restores both; Redo forward; `sourceStarts` stays 1 (S5, < 30 s)

## Phase 5: Polish

- [ ] SCN-010-T09 Amend docs/adr/0028-scene-document-format.md (history decisions); run `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`
- [ ] SCN-010-T10 Run projectM-iOSTests, SceneUndoUITests, SceneAutosaveUITests, NativeVisualUITests, ShowCueUITests on the own simulator; count PosterBoard reports after; delete the simulator; record results in spec Status

## Dependencies

T01 → T02 → T03; T02 → T04 → T05 → T06; T05 → T07 → T08; all → T09, T10. T03 and T04 can run in
parallel.
