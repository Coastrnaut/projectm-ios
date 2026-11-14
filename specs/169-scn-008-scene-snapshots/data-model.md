# Data Model: SCN-008

## SceneSnapshotEntry (SceneFormat)
`fields: [String: SceneJSON]`, verbatim. Known keys: `name` (string, 1…64 characters after trimming), `values` (object, ≤ 64 members, each `{"kind": continuous|integer|boolean|enum|color, "value": …}` keyed by parameter ID).

## SceneSnapshot (SceneFormat)
| Field | Type | Rule |
|---|---|---|
| name | String | as above |
| values | [ParameterID: ParameterValue] | decoded; IDs not checked against a registry |

## SceneSnapshotRecallPlan (SceneFormat)
`writes: [(id: ParameterID, value: ParameterValue)]` (sorted by ID, validated/clamped); `skipped: [(id: ParameterID, reason: SceneSnapshotSkipReason)]` with reason `unknownParameter`, `notSettable`, `rejected(String)`.

## Limits (SceneLimits)
`maximumSnapshots = 16`, `maximumSnapshotEntries = 64`, `maximumSnapshotValues = 64`, `maximumSnapshotNameLength = 64`.

## Issue codes (SceneIssue.Code, warnings)
- `invalidSnapshot` → repair group invalid mappings, no action; "It is kept in the scene but has no effect."
- `unknownSnapshotParameter` → unknown content, no action; "It is kept but not used by this version."

## App
- `SceneAutosaveCarry.snapshots: [SceneSnapshotEntry]?`
- `SceneSnapshotCoordinator`: `entries`, `rows`, `status`, `save()`, `rename(at:to:)`, `delete(at:)`, `recall(at:)`.
