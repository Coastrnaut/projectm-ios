# Data Model: SCN-006 Scene Preview Image

## ScenePreviewKey

| Field | Type | Rule |
|---|---|---|
| sceneID | String | SHOW-001 scene ID |
| contentHash | String | SHA-256 hex (64 lowercase digits) of the scene file's bytes |
| formatVersion | Int | `ScenePreviewStore.formatVersion` (1); bumped when the picture's size or crop changes |
| stableID | String | first 32 hex of SHA-256("scene\n" + sceneID + "\n" + hash + "\n" + version) |
| fileName | String | stableID + ".png" |

## Scene preview index (`Library/Caches/ScenePreviews/index.json`)

`PresetThumbnailIndex` (PRE-001 data model) with: `rendererVersion` = format version; each entry's
`presetID` = scene ID, `contentHash`, `rendererVersion`, `file`, `width` 192, `height` 108.

Rules: at most one entry per scene ID after a store; an entry is valid only when its hash equals the
scene file's current hash (the model checks); open-time repair as PRE-001.

## Pending capture (app, memory only)

token, sceneID, contentHash, look (`ShowLook`) at the apply; replaced by a later apply or save.

## State per scene (as shown)

no preview (placeholder) → captured (picture) → file changed or scene removed (placeholder, entry and
file removed) → captured again on the next apply.
