# Data Model: QA-004 Scene Migration Matrix

`Packages/SceneFormat/Tests/SceneFormatTests/Fixtures/legacy/matrix.json` (schema in
[contracts/migration-matrix.md](contracts/migration-matrix.md)).

| Entity | Fields | Rules |
|---|---|---|
| Container | `id`, `reader`, `test` (repo-relative file), `surfaces` (how current / migrated / refused show) | ids: decode, repairReport, showStore, archive, autosave, golden; the test file exists and contains `"<id>"` |
| Chain | `id`, `testOnly`, `target`, `steps` (identifiers) | `standard` = the app's chain; others `testOnly: true`, defined in each runner |
| Row | `id` (`QA-004-Mnn`), `title`, `versionJSON` (JSON text, or null = key removed), `format` (optional override), `chain`, `shape` (`as-is` or `v0-title`), `base` (`all` or a manifest file), `outcome`, `notApplicable` ({container: reason}) | exactly one outcome; a not-applicable reason is non-empty |
| Outcome | `kind` = `current` / `migrated` / `refused`; migrated: `from`, `to`, `log` (lines); refused: `error` (case name), `message` | `error` names an `errors` entry |
| Error entry | `case`, `code` (`refusal.<case>`), `group`, `severity`, `ifOpened`, `when`, `coveredBy` (rows or test names) | one per `SceneDecodeError` case |
| Migration error entry | `case`, `decodeError` | one per `SceneMigrationError` case |

A **cell** is (row, container) minus the row's not-applicable containers. Cells per container are
counted by the runner and compared with the matrix.
