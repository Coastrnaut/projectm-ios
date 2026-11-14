# Data Model: MOD-010 Parameter Macro

## MacroTarget (ParameterGraph)

| Field | Type | Rule |
|---|---|---|
| `parameter` | `ParameterID` | registered; continuous, integer or enum kind |
| `curve` | `MappingCurve` | valid (MOD-004 `validationProblem == nil`); default linear |
| `outputMinimum`, `outputMaximum` | `Double?` | nil = the parameter's bound (enum: 0 and cases − 1); finite; minimum ≤ maximum |
| `inverted` | `Bool` | default false |

## ParameterMacro (ParameterGraph)

| Field | Type | Rule |
|---|---|---|
| `name` | `String` | non-empty |
| `value` | `Double` | limited to 0…1 when used (non-finite → 0) |
| `targets` | `[MacroTarget]` | first 8 used; a later target on the same parameter is a duplicate |

Limits: `ParameterMacro.maximumTargets = 8`, `ParameterMacro.maximumMacros = 8`.

`evaluate(registry:)` → `MacroEvaluation { assignments: [MacroAssignment(parameter, value)], skipped:
[MacroSkip(index, parameter, problem)] }`.

## SceneMacroEntry (SceneFormat)

Every field verbatim (`fields: [String: SceneJSON]`). Read → `ParameterMacro?` by position (nil: unusable
entry). Issues: `invalidMacro`, `unknownMacroTarget` (warnings).

## App

- `MacroCoordinator.entries: [SceneMacroEntry]?` — the current scene's list (nil: none).
- `SceneInputs.macros`, `SceneAutosaveCarry.macros`, `SceneRestoredValues.macros`.
