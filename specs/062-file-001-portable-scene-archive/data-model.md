# Data Model: FILE-001 Portable Scene Archive

| Entity | Fields | Rules |
|---|---|---|
| SceneArchiveManifest | `format` = `projectm-ios.scene-archive`, `formatVersion` = 1, `files` [PortableFileRecord], `scene` = `scene.json`, `assets` [SceneArchiveAssetRecord] | Generic header and file list checked by `PortableArchive`; `scene` must be `scene.json`; asset keys unique; at most one `photo` and one `video`. |
| SceneArchiveAssetRecord | `key`, `type` (`photo`/`video`), `path` | `path == "assets/<key>.<ext>"`, ext `png`/`jpg` (photo) or `mov` (video); `key` valid SCN-001 asset key. |
| SceneArchiveMedia | `key`, `type`, `fileExtension`, `data` | The bytes packed or read; data passed the content check (reader). |
| SceneArchiveContents | `document` (SceneDocument), `media` [SceneArchiveMedia], `warnings` [SceneIssue] | Every photo/video asset of the document has one media item and vice versa; document has no validation errors (no availability check). |
| SceneArchiveError | one case per refusal (contract §4) | `message` readable. |
| SceneArchiveImportResult (app) | `document` (remapped), `photo` StoredPhoto?, `video` StoredVideo?, `replacedPhoto`, `replacedVideo` | References resolve in the stores. |
| SceneArchiveExport (app) | `url` (temporary file), `fileName` | Removed by `cleanUpExport()`. |

State of an import: read → checked → staged → validated (remapped against staged IDs) → committed
(files moved, identifiers switched, previous deleted) | failed (staged removed, stores unchanged).
