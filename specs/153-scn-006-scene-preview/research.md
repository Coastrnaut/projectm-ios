# Research: SCN-006 Scene Preview Image

## SCN-006-D1 Reuse PRE-001/PRE-002's cache design and code

- **Decision**: A new `ScenePreviewStore` actor in PresetLibrary's `Thumbnails` folder that stores
  through `PresetThumbnailIndex` unchanged: its entry's `presetID` holds the scene ID and
  `rendererVersion` the preview format version (1). Open-time repair, stale selection
  (`staleIDs`, `unlistedIDs`) and file removal (`removeEntries`) are reused as they are.
- **Rationale**: The index already does exactly what scenes need (content-hash keys, versioned JSON,
  repair, invalidation by owner ID, launch collection) and is tested. Placing the store in the same
  module uses the internal `removeEntries` without widening the public API, and leaves PRE-001's
  cache, its pull-based render queue and its tests untouched.
- **Alternatives**: Generalising `PresetThumbnailCache` (its queue renders from preset text; scenes are
  pushed pictures, so the queue does not fit); a copy of the index for scenes (duplicate code); a
  generic rename of the index (touches PRE-001 and its fixtures).

## SCN-006-D2 Key and invalidation

- **Decision**: `ScenePreviewKey(sceneID, contentHash, formatVersion)`; stable ID = first 32 hex of
  SHA-256 of "scene\n<id>\n<hash>\n<version>" (the "scene" prefix keeps it apart from preset IDs even
  though the folders differ). Content hash = SHA-256 hex of the scene file's bytes. Storing a preview
  removes the scene's entries for other hashes; `invalidate` on a file change; `retainOnly` with the
  show's listing on cue removal and at launch.
- **Rationale**: The roadmap's acceptance ("invalidates after edit") holds for any write, by
  construction: a different file never matches.

## SCN-006-D3 Capture

- **Decision**: REC-001's `FrameCaptureSource.captureFrame` on the shown visual (the next presented
  frame after flash limiting), 1 s timeout, skipped while `FrameCaptureCoordinator.isCapturing`; then
  `FrameColorConversion.rgba8(_, policy: .opaqueOverBlack)`, a centre crop to 16:9 and a Core
  Graphics scale to 192 × 108 (3× the 64 × 36 pt tile), PNG through PRE-001's `PNGThumbnailEncoder`.
  Conversion runs on a detached task.
- **Rationale**: Cheap, already rendered, exactly what the user saw. PNG keeps the reused index's file
  rules (`.png` only) and a 192 × 108 PNG is a few tens of KB.
- **Alternatives**: Offscreen rendering (rejected in the spec); HEIC (smaller, but the index's file
  rules are PNG and the gain at this size is small).

## SCN-006-D4 When a capture is kept

- **Decision**: Save: capture now. Apply: only when no preview exists for the current hash; after a 1 s
  settle (injected sleep) the capture runs only if the scene is still the applied one, its hash and
  the `ShowLook` are unchanged since the apply, the output is live and not paused. A later apply or
  save cancels the pending one (a token).
- **Rationale**: The preview must correspond to the saved scene (acceptance).

## SCN-006-D5 UI

- **Decision**: One `ScenePreviewView` tile (64 × 36 pt, rounded 6 pt, like PRE-001's
  `PresetThumbnailView`) at the leading edge of switcher rows and in place of the Folders row icon,
  `.accessibilityHidden(true)`. It loads with `.task(id:)` keyed by scene ID, hash and the model's
  revision.
