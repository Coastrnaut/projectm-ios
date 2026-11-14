# Data Model: UIX-004 Favorite Parameter Shelf

## Stored

| Key | Type | Rules |
|---|---|---|
| `settings.parameterShelf.pins` | `[String]` | Ordered parameter ID strings; absent = empty shelf. Unknown entries kept until removed. Included in library backups (FILE-005), erased with Settings (FILE-011), listed in `ALLOWED_KEYS`, cleared by `-uitestResetNotice`. |

## In memory

| Value | Fields | Rules |
|---|---|---|
| `ParameterShelf` | `entries: [String]` | Saved on every change. `pinned` = entries that are available, in order (≤ 8 by construction of `pin`); `missing` = the others. |
| Availability | — | registered in `VisualParameterCatalog` and in `ParameterInspectorTargets.inspectableIDs` (research UIX-004-D1). |
| Missing note | text | "1 pinned control is no longer available" / "N pinned controls are no longer available"; nil when none. |

## Transitions

- `pin(id)`: available, not pinned, fewer than 8 pinned → appended. Otherwise no change (returns false).
- `unpin(id)`: removes every entry equal to `id`.
- `move(from:to:)`, `moveUp(id)`, `moveDown(id)`: reorder `pinned`; entries = pinned + missing.
- `removeMissing()`: entries = pinned.
