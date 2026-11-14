# Contract: Scene A/B Compare (SCN-009)

## C1 Coordinator (`SceneCompareCoordinator`, main actor)
- `isActive: Bool`, `session: SceneCompareSession?`, `status: String?`
- `start(a: SceneCompareChoice, b: Int) -> String?` — nil when started; else the refusal ("Scene locked. Unlock the scene to edit.", "Choose two different states.", "That snapshot can't be used.")
- `show(_ side: SceneCompareSide) -> Bool`, `toggle()` — false when refused (locked) or not active
- `keep(_ side: SceneCompareSide) -> Bool` — false when refused (locked); Compare stays active
- `cancel()` — always ends Compare and restores the pre-Compare scene
- `abandon()` — ends Compare without restoring (history restart while suspended)
- Announcements: "Comparing A/B: A, <name>", "A, <name>" / "B, <name>", "Kept <name>", "Compare cancelled", "Compare ended"

## C2 Autosave (`SceneAutosaveCoordinator`)
- `suspend()`; `isSuspended`; `resume(from baseline: SceneInputs)`
- While suspended: `inputsChanged`, `commitNow`, `tick`, background and `flushSynchronously` write nothing and note no edit.

## C3 History (`SceneHistoryCoordinator`)
- `suspend()`; `isSuspended`; `resume()`; `onRestartWhileSuspended: (() -> Void)?`
- While suspended: `capture`, `recordStep` record nothing; `undo`, `redo` do nothing; `canUndo`, `canRedo` false.

## C4 Snapshots
- `SceneSnapshotCoordinator.isComparing: () -> Bool`; save, rename, delete, recall refused with "Finish Compare first." while it returns true.

## C5 UI identifiers
- Settings row: `sceneCompareOpen` ("Compare A/B…"); sheet pickers `sceneCompareA`, `sceneCompareB`; button `sceneCompareStart`
- Bar: `sceneCompareBar` (label "Comparing A/B"); toggle `sceneCompareToggle` (label "Compare side", value "A, <name>" / "B, <name>"), segments `sceneCompareSideA`, `sceneCompareSideB`; `sceneCompareDone`
- Dialog buttons: `sceneCompareKeepA`, `sceneCompareKeepB`, `sceneCompareCancel`
