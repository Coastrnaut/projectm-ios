# Data Model: PRE-017 Preset Restore Points

## UserPresetVersion

| Field | Type | Rule |
|---|---|---|
| sha256 | String | 64 lowercase hex; the text's file `versions/<sha256>.milk` |
| blobHash | String | git blob SHA-1 of the text |
| byteCount | Int | 1…524,288 (PresetImportLimits.maxFileBytes) |
| replacedAt | Date | when an edit or revert replaced this text |
| name | String | the preset's name at that moment |

Identity: `sha256` within one preset (unique per preset; a repeated text moves to the newest place).

## UserPresetHistoryFile (`history.json`)

`{ "schemaVersion": 1, "presets": [ { "presetID": "user/…", "versions": [UserPresetVersion…] } ] }`,
versions oldest first, presets in index order of first appearance. Newer `schemaVersion` → unavailable,
never written. Unreadable → renamed `history.unreadable.json`. Entries for unknown preset IDs or with
missing files are dropped at load.

## UserPresetVersionLimits

`perPreset = 10`, `total = 500`, `totalBytes = 50_000_000` (distinct texts counted once).

## Transitions

edit/revert of preset P from text X to Y: P's list gains X (now), pruned by limits; files: `versions/X` added
if absent, `files/X` removed, `files/Y` added; version texts no entry names removed.
remove P: P's list removed; its texts removed unless another entry names them.
