# Data Model: SCN-013 Scene Migration

| Entity | Fields | Rules |
|---|---|---|
| `SceneMigrationChange` | `kind` (`renamed`, `added`, `removed`, `transformed`, `version`), `path`, `newPath?`, `detail` | `renamed` carries `newPath`; paths use SCN-001 `ScenePath` form (`$.layers[0].values`). |
| `SceneMigrationLogEntry` | `step` (identifier), `fromVersion`, `toVersion`, `change` | One per change; the migrator adds one `version` entry per step. |
| `SceneMigrationStep` | `fromVersion`, `identifier`, `summary`, `transform: ([String: SceneJSON], inout SceneMigrationRecorder) throws(SceneMigrationError) -> [String: SceneJSON]` | Pure; must record every renamed, removed or transformed value; never sets `version`. |
| `SceneMigrator` | `steps` (ordered), `targetVersion` | `standard` = no steps, target `SceneDocument.currentVersion`. |
| `SceneMigrationResult` | `root`, `record` | |
| `SceneMigrationRecord` | `sourceVersion`, `targetVersion`, `log` | `migrated` = source ≠ target; `stepCount`, `changeCount` (excluding version entries). |
| `SceneMigrationError` | `notAScene`, `invalidVersion(text)`, `newerVersion(v)`, `missingStep(from:)`, `stepFailed(step:from:path:reason)` | Maps to `SceneDecodeError` (`notAScene`, `invalidVersion`, `newerVersion`, `migrationFailed`). |
| Original backup | file `<name>.v<N>.backup`, bytes = original file | Created once (exclusive), never overwritten; removed only with its show scene. |
| Autosave events | `migrated(from:to:steps:changes:)`, `keptOriginal(name)` | Privacy: numbers and fixed names only. |
| Report entry | group `formatUpdated`, severity note, code `migration.updated` | Never needs review. |
| Golden fixture row | `file`, `version`, `source`, `expected`, `covers` | `covers` tags checked for completeness by a test. |
