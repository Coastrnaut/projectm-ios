# Data Model: SCN-010 Scene Undo and Redo

All in memory; nothing is stored.

## SceneHistoryState<Value> (SceneFormat)

| Field | Type | Rule |
|---|---|---|
| bytes | `[UInt8]` | canonical SCN-001 bytes; equality of states = byte equality |
| value | `Value` | what the caller re-applies (app: `SceneInputs`; tests: `SceneDocument`) |

## SceneHistoryStep<Value>

| Field | Type | Rule |
|---|---|---|
| state | `SceneHistoryState<Value>` | undo list: the state before the edit; redo list: the state after it |
| label | `String` | the edit's name ("Bars 16") |

## SceneHistoryLimits

`maximumSteps` = 50, `maximumBytes` = 4 MB (4 × 1024 × 1024); both ≥ 1.

## SceneHistory<Value>

| Field | Rule |
|---|---|
| current | the state shown now |
| undoSteps | oldest first; `last` is undone next |
| redoSteps | farthest first; `last` is redone next |
| openKey | the coalescing key of the newest step, nil when closed |
| storedBytes | current + every step's bytes; ≤ maximumBytes unless current alone exceeds it |

Transitions: `record` → recorded (push, redo cleared) | coalesced (current replaced; step dropped if
back to its before-state) | unchanged (same bytes; current value replaced, nothing else). `undo` /
`redo` move one step and close the open key. `endCoalescing` closes the key. `reset(to:)` empties both
lists.

## App: SceneHistoryCoordinator

Holds the history of `SceneInputs`, the carry snapshot, and closures `inputs`, `apply`. Publishes
`canUndo`, `canRedo`, `undoLabel`, `redoLabel`. Started after the launch restore; `restart()` on
non-edits.
