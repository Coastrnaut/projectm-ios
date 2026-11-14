# Contract: Scene Lock (SCN-015)

## L1 Model
- `SceneLock.key == "settings.scene.locked"`; `SceneLock.refusalMessage == "Scene locked. Unlock the scene to edit."`
- `lock()`, `unlock()`, `refusesEdit() -> Bool`, `isLocked`; `announce: (String) -> Void`.

## L2 Guarded APIs (refuse with no change while locked)
- `ParameterInspectorTargets.target(for:settings:)?.set`
- `MacroCoordinator.setValue(_:at:)` → nil
- `SceneSnapshotCoordinator.save()` → false, `rename` → message, `delete`, `recall` → result with nothing applied
- `ShowCoordinator`: `addScene`, `addCopies`, `installImportedScene`, `duplicateScene`, `renameScene`, `remove`, `move`, `rename`, `setTransition`, `createFolder`, `renameFolder`, `moveFolder`, `moveScene`, `deleteFolder`, `addTag`, `removeTag`; refusals set `editorMessage`
- `SceneHistoryCoordinator.undo()`, `redo()`; `canUndo`, `canRedo` false

## L3 Not guarded
`ShowCoordinator.next/previous/go/goToScene`, the cue apply path, blackout, tempo, presets, MIDI/OSC live values, MIDI mappings.

## L4 UI identifiers
- Controls: `lockScene` (label "Lock scene"/"Unlock scene", value "Unlocked"/"Locked")
- Badge: `sceneLockBadge`; Settings: `sceneLockToggle`; confirmation button "Unlock"
