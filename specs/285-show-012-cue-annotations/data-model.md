# Data Model: SHOW-012 Cue Annotations

## ShowCue (extended)

| Field | Type | Rule |
|---|---|---|
| `operatorNote` | `String?` | nil = no note; otherwise `ShowCueNote.normalized` text of 1…500 characters |

- Set by `ShowCueList.setOperatorNote(cueID, to:)`: text is normalized; empty → nil; over 500 characters → throws
  `ShowEditError.invalidNote`; unknown cue → `.unknownCue`. Never changes position, order or other fields.
- Copied by Duplicate Scene (`insert(…, operatorNote:)`); kept by move, rename, skip and every other edit; removed with
  its cue.

## ShowCueNote (rules)

- `maximumCharacters = 500`
- `normalized(_ text) -> String?`: line separators → LF, Cc except LF removed, trimmed; nil when empty or too long.
- `stored(_ text) -> String?`: as `normalized` but cuts to 500 characters (then trims again) instead of refusing.

## show.json cue entry

`"note": "<text>"` — optional; see [contracts/show-cue-note.md](contracts/show-cue-note.md).
