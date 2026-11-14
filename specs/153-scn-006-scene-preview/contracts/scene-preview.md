# Contract: SCN-006 Scene Preview

## P1 `ScenePreviewStore` (PresetLibrary)

- `init(directory:)`; `open()` never fails (PRE-001 repair).
- `store(_ png: Data, for key: ScenePreviewKey) throws -> URL`: writes `<stableID>.png` atomically,
  records the entry, removes the scene's entries for other hashes, saves the index; the folder is
  created and excluded from backup.
- `cachedURL(for:) -> URL?`: the file when the entry exists and the file is on disk (else the entry is
  dropped).
- `invalidate(sceneID:keepingContentHash:) -> Int`: removes the scene's other entries and files
  (all when nil); other scenes untouched; saves only when something was removed.
- `retainOnly(_ listing: [String: String]) -> Int`: removes entries whose scene is not listed or is
  listed with another hash.
- `entryCount`, `entries(forScene:)`.

## P2 `ScenePreviewModel` (app)

- `sceneSaved(sceneID:)`: capture now; store under the current hash.
- `sceneApplied(sceneID:)`: if no valid preview, after `settle` (1 s) capture when the guard holds.
- `scenesChanged(_ ids:)`: rehash each, `invalidate` keeping the new hash (nil when the file is gone).
- `reconcile()`: `retainOnly` with every stored scene's hash.
- `image(forScene:) async -> UIImage?`; `revision` changes after every store or removal.

## P3 Capture source

`ScenePreviewCapturing.capture() async -> Data?` — a PNG of the live output, or nil. The live one
uses REC-001's `FrameCaptureSource`; tests inject one returning a known picture.

## P4 UI

Switcher rows and Folders scene rows show `ScenePreviewView`: identifier `scenePreview:<sceneID>` with a
picture, `scenePreviewPlaceholder:<sceneID>` without; hidden from accessibility; the row's label, value,
actions and identifier are unchanged.
