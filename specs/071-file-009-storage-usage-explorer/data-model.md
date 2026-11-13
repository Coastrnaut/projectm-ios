# Data Model: FILE-009 Storage Usage Explorer

Nothing is persisted. All values are computed on demand.

| Entity | Fields | Rules |
|---|---|---|
| `StorageCategory` | photos, videos, scenes, presets, importedAudio, recordings, sharesAndExports, caches, otherAppData | Fixed display order (`allCases`); `title` is the row label |
| `StorageEntry` | name, kind (file / directory / symbolicLink / other), contentBytes, spaceUsed | Only `file` entries are counted; `symbolicLink` and `other` are never entered or counted |
| `StorageWalkLimits` | maxDepth (32), maxEntriesPerWalk (100,000) | Both ≥ 0; reaching either marks the report incomplete |
| `StorageUsage` | contentBytes, spaceUsed, fileCount (Int64 / Int) | Sum over the category's regular files |
| `StorageRequest` | container path, roots per category (list of paths) | Roots outside the container or that are links are skipped |
| `StorageReport` | usage per category, totals, isComplete, skippedRoots | total = Σ categories; incomplete when a limit hits or a folder cannot be read |

State of the screen model: `idle → measuring → (report | idle on cancel)`; Refresh from any state
cancels the running measurement and starts a new one.
