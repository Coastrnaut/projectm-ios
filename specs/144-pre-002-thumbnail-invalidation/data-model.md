# Data Model: PRE-002 Thumbnail Invalidation

No stored format changes: `index.json` stays schema 1 (PRE-001 data-model).

## Preset change (in memory)

| Field | Meaning |
|---|---|
| `presetID` | The changed preset. |
| `keepingContentHash` | The current hash, or nil when the preset left the list. |

Derived in `UserPresetsCoordinator.refresh()` from the playable list before and after:
`old[id] != new[id]` → change (`new[id]` may be nil). Unchanged hashes (rename) produce no change.

## Library listing (in memory)

`[presetID: contentHash]` of every preset the browser lists. An index entry survives the launch
collection only if `listing[entry.presetID] == entry.contentHash`.

## Rules

- Stale = same `presetID`, `contentHash != keepingContentHash` (all when nil).
- Removing an entry removes its file `entry.file` (a safe file name, PRE-001) and its remembered
  failure; the index is saved only if something was removed.
- Entries of other presets are never read for writing: their file, ID and modification date stay.
- Renderer version: entries with `rendererVersion != spec.rendererVersion` are dropped at open
  (PRE-001-R8), so a v1 index opened by a v2 build is empty and all v1 files are gone.
