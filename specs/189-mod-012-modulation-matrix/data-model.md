# Data Model: MOD-012 Modulation Matrix UI

## AudioFeatureBinding (ParameterGraph, changed)

| Field | Type | Notes |
|---|---|---|
| … MOD-002 to MOD-005 fields | | unchanged |
| isEnabled | Bool | default true; false → skipped in the fold (MOD-012-R3) |

## Scene binding entry (`$.bindings[i]`, SCN-001, changed)

| Field | Type | Notes |
|---|---|---|
| enabled | boolean, optional | written only when false; absent = true (MOD-012-R5) |

## ModulationRouteGroup (ParameterGraph, new, pure)

| Field | Type | Notes |
|---|---|---|
| target | ParameterID | destination |
| layers | [AudioFeatureBinding] | fold order |

Groups appear in the order their destinations first appear in the binding list.

## SceneInputs (app, changed)

| Field | Type | Notes |
|---|---|---|
| bindings | [AudioFeatureBinding]? | nil: the caller does not track them (live/carried list kept); the app passes the matrix mirror |

## ModulationMatrixCoordinator (app, new)

- `routes: [AudioFeatureBinding]` (observable mirror), `groups`.
- `setEnabled(_:target:layer:)`, `move(target:from:to:)`, `restore(_:)`, `refresh()`.
