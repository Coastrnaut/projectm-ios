# Contract: Cache cleanup (FILE-010)

Code: `Packages/LocalPortability/Sources/LocalPortability/CacheCleanup.swift`; app side
`Apps/projectM-iOS/Coordinators/StorageLocations.swift`, `StorageUsageModel.swift`,
`AppCoordinator+CacheCleanup.swift`, `Views/StorageUsageView.swift`.

## C1 — Roots (FILE-010-R1, R3)

- Cleanable categories: `recordings`, `sharesAndExports`, `caches`.
- Protected roots (app): Photos, Videos, Scenes, UserPresets, PresetCollections, AudioLibrary (each
  under `Library/Application Support`), `Library/Application Support/Show`, `Library/Preferences`.
- A cache root is refused (`CacheCleanupPlan.refused`) when: its category is not cleanable
  (`notCleanable`); it is a link (`symbolicLink`); its resolved path is the container or not strictly
  inside it (`outsideContainer`); it equals, contains or lies inside a resolved protected root
  (`overlapsProtected`); it repeats an earlier root (`duplicate`). A missing root is not refused: it
  plans nothing.
- The root folder itself is never removed.

## C2 — Plan (FILE-010-R4, R5)

- Each root's children are listed one level at a time without following links.
- A child equal to, or inside, a resolved in-use path is kept (`keptInUse`).
- A folder child containing an in-use path is entered and its children planned the same way.
- Every other child is an item: a file (its usage), a link (zero usage, removed as a link), a folder
  (usage of the regular files below it, FILE-009 limits; `isComplete` false at a limit or unreadable
  folder), or other (zero).
- Item names that are empty, `.`, `..` or contain `/` are ignored.

## C3 — Execute (FILE-010-R4, R5, R9)

For each item, in plan order:

1. If the item is now in use (the fresh in-use set) it is kept.
2. If its parent no longer resolves to itself, or it is no longer strictly inside its root, or the root
   is no longer a folder, it is skipped as failed.
3. If nothing exists at the path, it is `vanished`.
4. Otherwise `removeItem(atPath:)`; an error makes it `failed` and the next item continues.

## C4 — Screen (FILE-010-R2, R6, R9)

- Section with a button "Clear Caches…" (`storageClearCaches`), disabled while measuring, planning or
  clearing.
- With items: alert "Clear Caches?" message "Frees <size>." (or "Frees about <size>." when the plan is incomplete), then " Photos, videos, scenes, the show, presets,
  imported audio and settings are kept." plus " Files in use are kept." when any were kept; buttons
  "Clear" (destructive, `storageClearConfirm`) and "Cancel".
- Without items: alert "Nothing to Clear" message "There are no caches to clear." (or "The remaining
  files are in use." when items were kept), button "OK".
- After clearing: the measurement refreshes; a note "Cleared <size>." (`storageCleanupResult`), and
  "Some files could not be removed." (`storageCleanupFailed`) when any failed.
