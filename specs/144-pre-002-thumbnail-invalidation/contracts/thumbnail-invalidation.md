# Contract: Thumbnail invalidation (PRE-002)

## C1 `PresetThumbnailCache.invalidate(presetID:keepingContentHash:) -> Int`

- Opens the cache if needed. Removes every index entry with this `presetID` whose `contentHash`
  differs from `keepingContentHash` (all when nil), deletes their files, forgets their remembered
  failures, and saves the index when at least one entry was removed. Returns the number removed.
- Cancels queued requests for keys of this preset with another hash (waiters throw
  `CancellationError`). A render in flight for such a key completes without storing; its waiters
  get `PresetThumbnailError.unavailable`.
- Never throws; touches no other preset's entry, file or failure.

## C2 `PresetThumbnailCache.retainOnly(_ listing: [String: String]) -> Int`

- Removes, with their files and failures, every entry whose `listing[presetID] != contentHash`.
  Saves the index only when something was removed. Returns the number removed. Never throws.

## C3 App

- `PresetThumbnailModel.invalidate(presetID:keepingContentHash:) async` evicts the in-memory
  pictures of that preset's other hashes, then calls C1.
- `PresetThumbnailModel.collectGarbage(listing:) async` calls C2.
- `UserPresetsCoordinator.refresh()` calls `invalidate` for each changed or removed playable user
  preset (after publishing the new list).
- `PresetCoordinator.attach(_:)` starts `collectGarbage` once with the full library listing.
- `PresetThumbnailView.requestID(for:playable:)` = `id + "\n" + hash (+ "\nlocked")`.

## C4 Renderer version

- `PresetThumbnailSpec.rendererVersion` is bumped by hand whenever thumbnails for the same preset
  would look different (spec fields, projectM pin or ANGLE update that changes drawing). Opening
  drops entries of other versions with their files (PRE-001 C-open, unchanged).
