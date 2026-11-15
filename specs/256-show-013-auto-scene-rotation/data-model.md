# Data Model: SHOW-013 Auto Scene Rotation

- **SceneRotationSettings** (stored as JSON in `settings.show.rotation`): `mode` (`timer` | `bars`, default timer),
  `intervalSeconds` (15…600, default 60), `bars` (1…64, default 8), `folderID` (UUID?, nil = all scenes),
  `disabledSceneIDs` ([String], sorted, unique). Missing or invalid fields decode to defaults; numbers are clamped.
- **SceneRotationPlan**: `collection` ([String], show order), `disabled` (Set<String>); `enabled` = collection minus
  disabled. `pick(current:seed:step:)` → `.scene(String)` | `.idle(.noScenes | .oneScene)`.
- **SceneRotationSchedule**: `deadline(after:settings:barLine:reduceFlashing:)` → (`at`: UInt64 ns, `onBeat`: Bool).
- **SceneRotationCoordinator state** (session only): `isOn`, `seed`, `step`, `deadline`, `status` (off, waiting(seconds
  or bars), held, showPlaying, idle reason), `rotations` (count of requested switches; tests and DEBUG probes).
