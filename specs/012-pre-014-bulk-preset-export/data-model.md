# Data model: PRE-014 Bulk preset export

No stored data changes. The user-preset record stays version 2 (PRE-015). New in-memory and
in-archive types:

## Preset archive (file)

`projectM-iOS Presets <yyyy-MM-dd>.zip`, a stored ZIP (research D2):

| Entry | Content |
|---|---|
| `presets/<uuid>.milk` | the stored preset text, byte for byte; one per exported preset, sorted by id |
| `manifest.json` | the manifest below, last |

## Manifest (format `org.projectmios.user-presets`, version 1)

Schema: [contracts/preset-archive-manifest-v1.schema.json](contracts/preset-archive-manifest-v1.schema.json).

| Field | Type | Rule |
|---|---|---|
| `format` | string | exactly `org.projectmios.user-presets` |
| `formatVersion` | integer | 1; a reader refuses a higher one as "newer" |
| `appVersion` | string | `"<short> (<build>)"`, informational, ≤ 40 characters |
| `exportedAt` | ISO 8601 string | whole seconds, UTC |
| `files` | array of FileRecord | one per preset text; paths unique |
| `presets` | array of ExportedPreset | ≤ 1,000; sorted by id |

**FileRecord** (`LocalPortability.PortableFileRecord`): `path` (safe relative path), `sha256`
(64 lowercase hex), `byteCount` (≥ 0 and ≤ the entry limit in the generic layer; the preset format requires ≥ 1, as
the schema says).

**ExportedPreset** (`PresetLibrary.ExportedUserPreset`):

| Field | From the record | Rule on read |
|---|---|---|
| `id` | `id` | `user/` + 1-75 of `[a-z0-9-]`; unique |
| `name`, `author` | same | PRE-012 lengths |
| `authorFromFileName` | `license.authorFromFileName` | |
| `originalFileName` | same | ≤ 255 |
| `path` | — | `presets/<id without user/>.milk`, listed in `files` |
| `sha256`, `byteCount` | same | equal to the `files` record and the text |
| `blobHash` | same | equals the git blob SHA-1 of the text |
| `origin` | `license.origin` | `userImport` or `bundledDuplicate` |
| `rightsVerified` | `license.rightsVerified` | must be false |
| `licenseLines` | `license.linesFound` | ≤ 5 lines |
| `warnings` | same | ≤ 50, `{code, detail}` |
| `duplicateOf` | same | present iff origin is `bundledDuplicate`; `packID` must be `included`, `requiresLibraryUnlock` false |
| `importedAt`, `modifiedAt` | same | ISO 8601; `modifiedAt` optional |

Read back, an ExportedPreset converts to a `UserPreset` with state `pending` (what PRE-013 will
store before its own checks) and must pass `UserPreset.isWellFormed`.

## Export plan (in memory)

`UserPresetExportPlan`: `exportable: [UserPreset]` (alphabetical) and `excluded: [Reason: Int]`.

| Reason | Which records | Summary words |
|---|---|---|
| `fullLibraryCopy` | `duplicateOf.requiresLibraryUnlock` or `duplicateOf.packID != "included"` | "copies of presets from the full library: they are part of the purchase and stay on this device" |
| `quarantined` | state quarantined | "in Quarantine: they failed a check" |
| `notChecked` | state pending (not a full-library copy) | "waiting to be checked" |
| `unavailable` | held after a failed save, an id that cannot name a file, or removed meanwhile | "could not be read" |

## Export summary

`UserPresetExportSummary`: `exported: Int`, `excluded: [Reason: Int]`, `fileName: String`;
`message` is one paragraph, e.g. "Exported 2 presets. Not exported: 1 copy of a preset from the
full library (part of the purchase; it stays on this device); 1 file in Quarantine (it failed a
check)."

## Errors

- `StoredZipError`, `PortableArchiveError` (LocalPortability) and `UserPresetArchiveError`
  (PresetLibrary): each case has a plain `message`. See the contract.
- `UserPresetExportError`: `nothingSelected`, `libraryUnavailable`, `contentMismatch`,
  `writeFailed`; message "The presets could not be exported. Nothing was shared." (plus the
  newer-format sentence for `libraryUnavailable`).

## State on the device

| Path | Life |
|---|---|
| `<tmp>/PresetExport/<uuid>/<file name>.zip` | created by Export; deleted when the share sheet closes, on any export error, and (the whole `PresetExport` folder) at the next `load()` |
