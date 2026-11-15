# Data Model: PRE-011 Preset Notes

## PresetNoteMap (value type, `PresetLibrary`)

| Field | Type | Rules |
|---|---|---|
| `notes` | `[String: String]` | preset ID (1-512 UTF-8 bytes) → trimmed text, 1-2,000 characters; at most 20,000 entries |

Operations: `note(for:)`, `set(_:for:)` (trims; empty removes; too long → `tooLong(limit:)`; bad ID → `invalidPreset`;
over the count → `tooManyNotes(limit:)`), `remove(_:)`, `presetIDs(containing:)` (folded substring),
`repaired(_:)` (lenient read; drops and counts).

## PresetNotesFile

`{ "schemaVersion": 1, "notes": { "<preset ID>": "<text>" } }` — see contracts/notes-file.md.

## PresetNoteStore

`map`, `availability` (`available` | `newerFormat(version:)`), `loadNotice` (`none` | `unreadableSetAside` |
`repaired(dropped:)`), `set(_:for:)`, `remove(_:)`, `prune(_:)`. Every change is saved atomically before it is
visible; a failed save throws `saveFailed` and changes nothing.

## Backup (`LibraryBackup`)

`LibraryContents.presetNotes: PresetNoteMap?`, `LibraryRestorePlan.presetNotes`, record `collections/notes.json`,
digest key `preset-notes`, `LibraryFolders.notesFile`.

## Integrity

`PresetReferenceStore.notes`, `PresetReferenceSnapshot.notes: [String]` (preset IDs with a note).
