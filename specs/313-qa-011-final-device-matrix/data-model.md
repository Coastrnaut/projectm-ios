# Data Model: QA-011 Final physical device matrix

## InventoryEntry (device-inventory.json `tasks[]`)

| Field | Type | Rule |
|---|---|---|
| `id` | string | task ID as written (`PERF-001-T16`, `T087`); unique per spec |
| `spec` | string | spec directory name |
| `feature` | string | roadmap ID from the spec directory (`PERF-001`) or `001`/`002` |
| `line` | int | 1-based line in tasks.md |
| `tags` | [string] | `device`, `owner` |
| `status` | enum | `open`, `optional`, `waived` |
| `category` | enum | `a`, `b`, `c` |
| `session` | string? | owner session ID for `b`; `MATRIX` for `a`; null for `c` and waived |
| `devices` | [D1/D2/D3] | sorted |
| `devicesInferred` | bool | true when no device was named |
| `estimatedMinutes` | int | (5 + minutes the step names) × devices; 0 when in no session |
| `matrixCases` | [string] | cases that close it (`a`) or cover a scripted part (`b`) |
| `text` | string | full step text (continuation lines joined with one space) |

Top level: `kind` `projectM-iOS.qa011.deviceInventory`, `schemaVersion` 1, `source` (`specs/*/tasks.md`),
`counts` (`total`, `byCategory`, `byStatus`, `byDevice`, `bySession`, `specs`), `sessions[]`, `matrixCases[]`,
`tasks[]`. No timestamps or commit: the same tasks give the same bytes.

## OwnerSession

`id` (B01-B13), `order`, `title`, `devices`, `install` (which build), `preparation` [string], `record` [string],
`tasks` [id], `estimatedMinutes`.

## MatrixCase

`id`, `kind` (`autorun`, `launches`, `warmstart`, `thresholds`, `xctest`), `title`, `devices`, `closes` [task id],
`timeoutSeconds`, plus kind fields: `mode`, `prefix` (autorun); `package` or `app`, `onlyTesting`, `env`,
`configuration` (xctest).

## RunRecord

See [contracts/run-record.md](contracts/run-record.md). Case status transitions: `not-run` → `pass` | `fail` |
`timeout` | `error` | `blocked` | `skipped`; after a `blocked` case every later case stays `not-run`.
