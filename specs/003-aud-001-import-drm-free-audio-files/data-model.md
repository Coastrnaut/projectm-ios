# Data Model: AUD-001 Import DRM-free audio files

## Storage layout

```text
<Application Support>/AudioLibrary/
├── index.json               # the library record (below)
├── index.damaged.json       # only after a recovery: the unreadable record, kept aside
├── assets/<sha256>.<ext>    # one immutable copy per distinct content
└── incoming/<uuid>.<ext>    # imports in flight; emptied at every load
```

## ImportedTrack

| Field | Type | Rule |
|---|---|---|
| `id` | UUID | stable identifier; generated at import |
| `title` | String | picked file name without extension; trimmed; at most 200 characters; "Untitled" if empty |
| `originalFileName` | String | last path component of the picked URL, at most 255 characters; never a path |
| `sha256` | String | 64 lowercase hex digits of the content; unique within the library |
| `fileName` | String | `<sha256>.<ext>` or `<sha256>`; relative to `assets/`; must not contain `/` or `..` |
| `byteCount` | Int64 | bytes copied; 1 … 524 288 000 |
| `durationSeconds` | Double | frames ÷ sample rate; > 0 |
| `sampleRate` | Double | > 0 |
| `channelCount` | Int | 1 or 2 |
| `importedAt` | Date | clock at import (ISO-8601 in JSON) |

No absolute path, picked location, bookmark or playback history (AUD-001-R11).

## AudioLibraryIndex (`index.json`)

```json
{ "schemaVersion": 1, "tracks": [ { "id": "…", "title": "…", … } ] }
```

- `tracks` is stored in import order (oldest first); the UI shows it reversed (AUD-001-R10).
- Entries that fail the field rules above are dropped on load (treated as untrusted, like the files).

### Versioning

- `AudioLibraryIndex.currentSchemaVersion = 1`.
- Load decodes `schemaVersion` alone first. Greater than current → library unavailable, nothing
  written (AUD-001-R15). Lower → run the pure migration chain `migrate(_ data:from:)` (empty in
  version 1), write the result atomically, and keep the previous file until that write succeeds.
- Later features extend the record by adding fields and bumping the version: AUD-003 a queue order,
  AUD-004/005 repeat and shuffle state, AUD-006 nothing persistent. Unknown keys are ignored when
  decoding, so adding optional fields is also backward compatible.

## AudioLibraryState

`ready` | `unavailable(newerFormat)` | `unavailable(storage)` (the folder cannot be created or read).
When unavailable, `tracks` is empty and import and removal return `libraryUnavailable`.

## AudioImportOutcome (per picked file)

`imported(track)` | `duplicate(existing track)` | `failed(fileName, AudioImportError)`.

`AudioImportError`: `notAudio`, `unreadable`, `protectedContent`, `tooLarge(limitBytes)`,
`unsupportedChannelCount(count)`, `insufficientStorage`, `sourceUnavailable`, `libraryUnavailable`.

## Import state machine (one file)

```text
picked → typeChecked → copying(incoming) → hashed
       → [hash in library] → duplicate (temp deleted)
       → inspected → moved(assets) → indexed → imported
any failure → temp deleted (and new asset deleted if the index write failed) → failed(reason)
```

## InAppPlaybackTrack

`reference` (the bundled track) | `file(URL)` (a library asset URL, resolved at play time from
`fileName`; never persisted).
