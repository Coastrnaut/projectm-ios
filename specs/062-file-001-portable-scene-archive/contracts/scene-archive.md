# Contract: Scene Archive (FILE-001, format version 1)

## 1. Layout

A stored ZIP (PRE-014 contract `specs/012-pre-014-bulk-preset-export/contracts/preset-archive.md`
§1-3) with exactly:

```text
scene.json              SCN-001 canonical bytes
assets/<key>.png|jpg    the stored photo (if the scene has a photo asset)
assets/<key>.mov        the stored video (if the scene has a video asset)
manifest.json           written last
```

## 2. manifest.json

```json
{"assets":[{"key":"photo1","path":"assets/photo1.png","type":"photo"}],
 "files":[{"byteCount":123,"path":"scene.json","sha256":"…"},{"byteCount":456,"path":"assets/photo1.png","sha256":"…"}],
 "format":"projectm-ios.scene-archive","formatVersion":1,"scene":"scene.json"}
```

Sorted keys, no white space (JSONEncoder `.sortedKeys`); assets sorted by key; files: scene first,
then assets by key.

## 3. Limits

| Item | Limit |
|---|---|
| Archive file | 600,000,000 bytes, checked before reading |
| Files besides manifest | 3 |
| manifest.json | 65,536 bytes |
| scene.json | 1,048,576 bytes (SCN-001) |
| photo entry | `ImageImportLimits.standard.maxFileBytes` (40 MiB) |
| video entry | `VideoImportLimits.standard.maxFileBytes` (500 MiB) |

## 4. Refusals (`SceneArchiveError`, checked in this order)

| Case | Error |
|---|---|
| File larger than the archive limit | `archiveTooLarge(limit:)` |
| ZIP or manifest problem (PRE-014: unsafe/absolute path, `..`, duplicate, too many entries, entry too large, compressed, encrypted, symbolic link, CRC, missing/malformed manifest, wrong format, unlisted or missing file, length or SHA-256 mismatch) | `archive(PortableArchiveError)` |
| Newer format version | `archive(.newerVersion(n))` |
| Scene-archive keys missing or wrong (`scene` ≠ `scene.json`, bad record, unknown type, duplicate key, path ≠ `assets/<key>.<ext>`) | `malformedManifest(String)` |
| More than one photo or video record | `tooManyMedia(type)` |
| `scene.json` not listed | `missingScene` |
| A listed file that is neither scene nor asset | `unexpectedFile(path)` |
| An asset record's path not in the file list | `missingAssetFile(path)` |
| Scene decode refusal | `sceneRefused(SceneDecodeError)` |
| Scene validation errors | `sceneInvalid([SceneIssue])` |
| A photo/video asset without a record, a record without such an asset, or types differ | `mismatch(key)` |
| Asset first bytes are a program/script | `executableContent(path, ExecutableKind)` |
| Asset first bytes are an archive | `nestedArchive(path)` |
| Asset bytes not of the declared type | `wrongContent(path)` |
| Asset larger than its type's limit | `assetTooLarge(path)` |

Writer: `missingMedia(key:)` (asset not in the stores), `tooManyMedia`, `mismatch`, `wrongContent`,
`sceneInvalid` (the document has errors), `writeFailed`. App service (`SceneArchiveServiceError`) wraps
these as `archive(_)` and adds `unreadable` (file cannot be read), `media(path:message:)` (the store's
import refused the bytes; its message), `saveFailed` (staging or commit write failed) and
`unresolved` (a guard: references still missing after remapping).

## 5. Export

`SceneArchiveWriter.write(document:media:modified:sink:)`: refuses documents with validation errors
(caller passes the registry), packs `scene.json` = `document.encoded()`, then each media file, then the
manifest. The service gets media only from `PhotoStore.existingFile(for:)` / `VideoStore.existingFile(for:)`.

## 6. Import

`SceneArchiveReader.read(_ data:, registry:) throws(SceneArchiveError) -> SceneArchiveContents`. The
service then stages media through the stores, remaps (`remappingStoreIDs`), validates against the
staged IDs (no errors, no `missingAsset`), commits, and returns the result. Any failure: stores
unchanged, staging removed.
