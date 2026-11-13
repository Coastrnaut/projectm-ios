# Contract: Bounded JSON validation and document schemas (FILE-007)

## C1 Validator

`BoundedJSON.validate(_ data: Data, limits: JSONLimits) throws(JSONShapeError) -> JSONShapeSummary`

1. `data.count > limits.maxBytes` → `tooLarge` (no byte read). Empty or only white space → `empty`
   / `unexpectedEnd`. `EF BB BF` at the start → `byteOrderMark`.
2. RFC 8259 grammar, one value surrounded by optional white space; anything after → `trailingData`.
3. The first refusal wins; offsets are byte indexes into `data`.
4. With `requiresObjectRoot`, a first value that is not `{` is refused as `notAnObject` at its offset
   (before reading it). Brackets inside strings are text. Depth counts open containers (top level = 1).
5. Duplicate keys compare the decoded key (escapes resolved).
6. `bytesExamined ≤ offset + 1` on refusal and `= data.count` on success.

## C2 Document schemas (one per document, declared next to its format)

| Schema | Declared in | Limits (bytes / depth / string / number / elements) | Versions |
|---|---|---|---|
| `SceneArchiveFormat.manifestSchema` (`projectm-ios.scene-archive`) | SceneArchive | 65,536 (the reader's `maxManifestBytes`) / 8 / 4,096 / 32 / 256 | 1…1 |
| `UserPresetArchiveFormat.manifestSchema` (`org.projectmios.user-presets`) | PresetLibrary | 4 MiB / 8 / 16,384 / 32 / 4,096 | 1…1 |
| `UserPresetsFile.schema` (`org.projectmios.user-presets-file`) | PresetLibrary | 4 MiB / 8 / 16,384 / 32 / 4,096 | 0…2 |
| `PresetCollectionsFile.schema` (`org.projectmios.preset-collections`) | PresetLibrary | 16 MiB / 8 / 16,384 / 32 / 16,384 | 0…1 |

All refuse duplicate keys. The two archive manifests require an object root; the two local files
accept any top-level value, because a version-0 document (an older format with no version field) has
no fixed shape and only a migration step reads it.

## C3 Archive manifests

`PortableArchive.read(_:schema:limits:)` validates `manifest.json` with `schema.limits` (its `maxBytes`
capped by the archive's `maxManifestBytes`) before decoding anything; a refusal is
`PortableArchiveError.manifestRejected(JSONShapeError)`. Messages:
- grammar family: "The archive's manifest is not valid JSON."
- limit family: "The archive's manifest is too large or too deeply nested to read."
- duplicate key: "The archive's manifest lists the same field twice."

## C4 Local files

`PresetCollectionsFile.decode` and `UserPresetsFile.decode` validate first; any refusal → `ReadError.unreadable`.
