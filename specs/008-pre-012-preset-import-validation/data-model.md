# Data model: PRE-012

## UserPreset (one record in `index.json`)

| Field | Type | Rule |
|---|---|---|
| `id` | string | `user/<lowercase uuid>`; permanent; unique |
| `name` | string | display name: file name without extension, cleaned, 1-120 characters |
| `author` | string | text before the first " - " of the name, or empty; a guess |
| `originalFileName` | string | cleaned display text, at most 255 characters; never a path |
| `sha256` | string | 64 lowercase hex; names the stored file `<sha256>.milk` |
| `blobHash` | string | 40 lowercase hex; git blob SHA-1, comparable with the built-in index and the takedown list |
| `byteCount` | int | 1…524,288 |
| `importedAt` | date | ISO 8601 |
| `state` | `pending` \| `playable` \| `quarantined` | see plan state machine |
| `provenOnScreen` | bool | true after 3 s on the visible renderer |
| `quarantine` | reason? | present exactly when `state == quarantined` |
| `warnings` | [warning] | at most 50 |
| `license` | LicenseMetadata | |

Uniqueness: `id`, and `sha256` across all records.

## QuarantineReason

`{ code, detail? }`. Codes: `binaryContent`, `lineTooLong`, `tooManyLines`, `missingHeader`,
`noSettings`, `blockTooLarge`, `statementTooLong`, `nestingTooDeep`, `statementTooComplex`,
`tooMuchControlFlow`, `unbalancedEquation`,
`incompleteShader`, `engineRejected` (detail: engine message, cut to 300 characters),
`timedOut`, `interruptedDuringCheck`, `interruptedOnScreen`, `failedOnScreen` (detail). An unknown
code read from disk is kept and shown as "could not be used".

## ImportWarning

`{ code, detail }`. Codes: `missingTexture` (texture name), `numberingGap` (block name),
`ignoredLines` (count), `repeatedKeys` (count), `notUTF8`.

## LicenseMetadata

| Field | Value |
|---|---|
| `origin` | `userImport` |
| `rightsVerified` | `false` (always, in this feature) |
| `authorFromFileName` | bool |
| `linesFound` | up to 5 strings of at most 200 characters, verbatim |

## Trial records (`trial.json`, `proving.json`)

`{ schemaVersion: 1, presetID, phase: "trial" | "proving" }`, one file per phase, at most one of
each. An unreadable record, or one whose phase does not match its file, is removed and ignored
(it names nothing).

## Document (`index.json`)

`{ schemaVersion: 1, presets: [UserPreset] }` in import order. Limits: 1,000 non-quarantined,
200 quarantined, 4 MiB. Reading: current version decoded and checked (unique ids and hashes,
valid hex, `quarantine` consistent with `state`); newer → unavailable, untouched; older → pure
migration steps; anything else → set aside as `index.unreadable.json`.

## Scope

`PresetScope.user`, stored as `user`. Members: playable user presets, alphabetical by name then
id. An empty My Presets does not stay the chosen scope.
