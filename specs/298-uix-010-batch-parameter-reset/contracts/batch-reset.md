# Contract: UIX-010 Batch Parameter Reset

## B1 `ParameterBatchReset.reset(_:settings:history:)` (main actor)

1. Locked (`settings.sceneLock.refusesEdit()` true) → `.refused`, message `SceneLock.refusalMessage`, nothing written, no step.
2. `history.endCoalescing()`.
3. For each selected ID with a catalog descriptor and a write target, in catalog order: skip when `target.get() == defaultValue`, else `target.set(defaultValue)`.
4. Nothing written → `.alreadyAtDefaults`, message "Already at defaults", no step.
5. Else `history.recordStep(label:)` with "Reset <name>" (one) or "Reset <n> Parameters"; message "Reset <name>" / "Reset <n> parameters".

## B2 Parameter list identifiers

| Element | Identifier | VoiceOver |
|---|---|---|
| Select / Done | `parameterReset.select` | "Select" / "Done" |
| Toggle row | `parameterResetToggle.<id>` | label name; value "Selected"/"Not selected", group, value; toggle trait |
| Group Select All | `parameterResetSelectAll.<group id>` | "Select All <group>" / "Deselect All <group>" |
| Reset button | `parameterReset.reset` | "Reset <n> parameters to defaults"; disabled at 0 |
| Status | `parameterReset.status` | the last message |
| Undo / Redo | `sceneUndo` / `sceneRedo` | SCN-010 |

Announcements: reset and "Already at defaults" on the `.parameter` lane; a refusal is announced by the lock.
