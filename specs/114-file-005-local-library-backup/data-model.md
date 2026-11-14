# Data Model: FILE-005 Local Library Backup

## Archive layout (`.pmbackup`, format version 1)

```text
show/show.json                      ShowCueList canonical bytes (absent when the library has no show file)
show/scenes/<SCENE-ID>.scene.json   SCN-001 canonical bytes, one per stored readable scene
current/current.scene               SCN-001 canonical bytes of the current scene (absent when none)
presets/index.json                  UserPresetsFile (version 2) of the included presets
presets/texts/<sha256>.milk         each included preset's text
collections/collections.json        PresetCollectionsFile canonical bytes (absent when none)
settings.json                       {"schemaVersion":1,"values":{key: {"type":..., "value":...}}}
photos/<UUID>.png|jpg               each photo file
manifest.json                       written last (below)
```

## Manifest

| Field | Meaning |
|---|---|
| `format`, `formatVersion`, `files` | FILE-002 header: name, 1, every entry's path, sha256, byteCount |
| `appVersion` | CFBundleShortVersionString (build) of the writer |
| `createdAt` | ISO 8601, UTC |
| `counts` | `scenes`, `cues`, `currentScene` (0/1), `presets`, `collections`, `favorites`, `settings`, `photos` |
| `excluded` | `fullLibraryCopies`, `quarantinedPresets`, `videos`, `importedAudio` |

## LibraryContents (logical library)

- `showBytes: Data?`, `scenes: [String: Data]` (ID → canonical bytes), `currentScene: Data?`
- `presets: [LibraryPreset]` (record with `state` pending, text bytes), in index order
- `collections: [PresetCollection]?` (nil = no file)
- `settings: [String: LibrarySettingValue]` (included keys only; `favorites` and `lastPresetID` included)
- `photos: [String: Data]` (file name → bytes)
- `excluded: LibraryExclusions`

## LibrarySettingValue

`bool(Bool) | int(Int) | double(Double) | string(String) | strings([String]) | data(Data)`; JSON
`{"type":"bool","value":true}`; data as base64.

## Restore plan

- `choice: LibraryRestoreChoice` (`keepBoth` default, `replace`, `skip`), `overrides: [String: choice]`
  keyed by record key.
- `entries: [LibraryRestoreEntry]`: `key`, `kind` (`new`, `identical`, `clash`), `choice` (clash only),
  `outcome` (`add`, `addCopy(id, name)`, `replace`, `keep`, `none`), `fellBack` (Keep both kept the
  device's value).
- `showMode`: `exact` (empty show) or `merge` (FILE-004 scene plan), `refusal` (limits, unreadable
  library).
- `libraryDigest`: SHA-256 of the current `LibraryRecords` (detects change between plan and install).
- Counts per kind for the preview.

## Restore journal (`LibraryRestore/restore.journal.json`)

`{"schemaVersion":1,"phase":"prepared"|"committed","folders":[{"name":"Show","hadLive":true}],
"settings":{...},"removedSettings":[...]}`. `prepared` → roll back; `committed` → roll forward.

## Restore request (`LibraryRestore/pending/`)

`backup.pmbackup` (copy of the picked file), `request.json` `{"schemaVersion":1,"choice":"keepBoth",
"backupSHA256":"…"}`. Result: `LibraryRestore/last-result.json` `{"restored":true,"message":"…"}`,
read once by the Backup section.
