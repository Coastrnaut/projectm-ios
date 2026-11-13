# Contract: Scene migration (SCN-013)

## M1 Decode order

`SceneDocument.decode(bytes, migrator: .standard)`: size → bounded parse → **migrate** (format check,
version check, chain) → count limits → typed decoding. The result carries `migration:
SceneMigrationRecord` (source = target = 1 for every current file).

## M2 Refusals

| Input | Error |
|---|---|
| not an object / wrong `format` | `notAScene` |
| missing, non-number, fractional or < 1 version with no step | `invalidVersion(text)` |
| version > target | `newerVersion(v)` |
| version < target with no step from it | `migrationFailed(fromVersion: v, step: nil, path: "$.version", reason: "no step from version v")` |
| a step throws | `migrationFailed(fromVersion:, step: id, path:, reason:)` |

## M3 Steps

A step receives the document object without changing `version`; it returns the new object and
records each change. Unknown fields are kept unless the step names them. The migrator then sets
`version = from + 1` and records a `version` change at `$.version`.

## M4 Backups (app and ShowStorage)

Before the first save that replaces (or, for the autosave `.bak`, removes) a stored file whose
content decoded with `migration.migrated`, the file's original bytes are written to
`<file name>.v<sourceVersion>.backup` in the same folder, exclusively. An existing backup is kept. A
failed backup write refuses that save; the original stays.

## M5 Diagnostics

`migrated scene from version N to M (S steps, C changes)`; `kept original as <file name>`. No paths,
names, IDs or values.

## M6 Report

A migrated document's `SceneRepairReport` has exactly one `formatUpdated` note (`migration.updated`).

## M7 Fixtures

Every manifest row's input decodes; `encoded()` equals the expected file byte for byte; every input
leaf survives or is listed by the log; the rows' `covers` together include every layer kind, every
asset type, parameter values, bindings (each mix, an envelope, an expression), modulation generators
and connections, unknown content and each real writer.
