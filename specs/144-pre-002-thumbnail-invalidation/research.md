# Research: PRE-002 Thumbnail Invalidation

## PRE-002-D1: Where user preset changes are observed

- **Decision**: In `UserPresetsCoordinator.refresh()`: it reads the library snapshot after every
  change (edit, remove, import, archive install, quarantine, unlock change) and hands the playable
  list to `PresetCoordinator.setUserPresets`. Before overwriting `playable`, compare the old ID →
  content hash map with the new one; every ID whose hash changed is invalidated keeping the new
  hash, every ID that left is invalidated keeping nothing.
- **Rationale**: one hook covers every path, including ones added later; no change to
  `UserPresetLibrary`'s store.
- **Alternatives**: hooks in each action (`saveEdit`, `remove`, `installArchive`, …): misses
  quarantine and unlock changes; a notification from `UserPresetLibrary`: wider change for an S row.

## PRE-002-D2: Rename

- **Decision**: no invalidation; the key has no name in it and a user preset's ID is
  `user/<random>`. Tested (S4).

## PRE-002-D3: Renderer version

- **Decision**: keep PRE-001's hand-bumped `PresetThumbnailSpec.rendererVersion` and its open-time
  drop. Document in the spec type that a projectM pin or ANGLE update that changes pictures bumps it.
- **Rationale**: dropping at open is one pass before any request (cheaper than a per-request check,
  which would also need a sweep to delete files). Hashing the pins in would discard every picture on
  pin moves that change nothing visible.
- **Alternatives**: lazy per-entry check: same result, files linger; automatic pin hash: wasteful.

## PRE-002-D4: Launch collection

- **Decision**: `retainOnly([presetID: contentHash])` after `PresetCoordinator.attach` (library with
  built-in and playable user presets), once per launch, in a detached task on the cache actor.
- **Rationale**: catches changes made outside a live refresh (pack updates in an app update, a
  removal whose index write failed) without timers. Presets outside the listing (waiting, locked
  copies) lose their pictures, which are rebuildable.

## PRE-002-D5: Requests racing an invalidation

- **Decision**: queued requests for an invalidated ID are cancelled (waiters get
  `CancellationError`); an in-flight render of one is marked, and on completion its picture is not
  stored and its waiters get `unavailable` (not remembered).
- **Rationale**: otherwise the contents loader, which reads the preset's current bytes by ID, could
  store the new content's picture under the old ID.

## PRE-002-D6: Row refresh

- **Decision**: no new notification. `PresetThumbnailView`'s request identity is
  `id + hash (+ locked)`; when refresh publishes the new `IndexedPreset`, SwiftUI restarts the task.
  The identity becomes a static function so an app unit test checks it changes on an edit and not on
  a rename.
