# Data Model: FILE-007 Document Schema Validator

## JSONLimits (value)

| Field | Meaning |
|---|---|
| `maxBytes` | Total input bytes; checked before reading. |
| `maxDepth` | Open arrays/objects at once (top-level object = 1). |
| `maxStringBytes` | Raw bytes between the quotes of one string (escapes counted as written). |
| `maxNumberBytes` | Characters of one number. |
| `maxElements` | Elements of one array, or members of one object. |
| `rejectsDuplicateKeys` | Same decoded key twice in one object is refused. |
| `requiresObjectRoot` | The top-level value must be an object. |

## JSONShapeError (enum; every case carries `offset`, the byte index where reading stopped)

`tooLarge(bytes:limit:)` (offset 0), `empty`, `byteOrderMark`, `invalidUTF8`, `nestingTooDeep(limit)`,
`stringTooLong(limit)`, `numberTooLong(limit)`, `tooManyElements(limit)`, `duplicateKey`,
`invalidNumber`, `invalidEscape`, `controlCharacter`, `unterminatedString`, `unexpectedCharacter`,
`unexpectedEnd`, `trailingData`, `notAnObject`. Each has a family: grammar, limit or duplicate key,
which picks the readable sentence (spec Clarifications).

## JSONShapeSummary (value)

`bytesExamined`, `deepest`, `values`.

## DocumentSchema (value)

| Field | Meaning |
|---|---|
| `name` | Format name (the manifest's `format`, or a registry name for local files). |
| `oldestReadableVersion` | Older versions are refused (or migrated from, for local files). |
| `currentVersion` | Newer versions are refused with the reader's "made by a newer version" error. |
| `limits` | `JSONLimits`. |

Verdict for a version: `current`, `older` (migrate), `newer` (refuse), `unsupported` (below oldest).
