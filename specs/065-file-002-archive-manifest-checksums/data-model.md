# Data Model: FILE-002 Archive Manifest Checksums

## File record (unchanged; PRE-014)

| Field | Type | Rule |
|---|---|---|
| `path` | string | safe relative path, unique ignoring case, not `manifest.json` |
| `sha256` | string | exactly 64 characters `0-9a-f`; otherwise `invalidRecord(path)` |
| `byteCount` | integer | ≥ 0; otherwise `invalidRecord(path)`; must equal the entry's size |

## Refusals (PortableArchiveError, per entry)

| Case | Message (path = the entry) |
|---|---|
| `zip(.checksumMismatch(path))` | "path in the archive is damaged (checksum mismatch)." |
| `lengthMismatch(path)` | "path in the archive is not the size its manifest gives." |
| `checksumMismatch(path)` | "path in the archive does not match its manifest checksum." |
| `invalidRecord(path)` (new) | "The manifest's record for path has an invalid size or checksum." |
| `missingFile(path)`, `unlistedFile(path)`, `duplicateListing(path)`, `unsafePath(path)` | unchanged |

## Import step (app, new)

`SceneArchiveImportStep`: `.verified` → `.staged(path)` (per media file, key order) →
`.adopted(SceneArchiveAssetType)` → `.madeCurrent(SceneArchiveAssetType)`. Only `.verified` and
`.staged` precede the commit; `.adopted`/`.madeCurrent` touch the real stores.

## Incremental hasher (new)

`PortableSHA256.Hasher`: state 8 × UInt32, pending bytes (< 64), total length; `update(_:)` with
`Data` or `[UInt8]`, any number of times; `finalize() -> String` (lowercase hex). Equal to
`PortableSHA256.hex` for any split of the input.
