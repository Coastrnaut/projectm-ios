# Data Model: MIDI-012 MIDI Mapping Profiles

| Entity | Fields | Rules |
|---|---|---|
| Profile (`MIDIProfile`) | `id` (UUID string), `name`, `lines: [String]`, `link: Int32?` | name 1-60 characters, unique in the store; ≤ 512 lines, each ≤ 256 UTF-8 bytes, no control characters; `link` is a system unique number (never a fallback ID), local only. |
| Store file (`MIDIProfileStoreFile`) | `format` = `org.projectmios.midi-profiles`, `version` = 1, `profiles` | ≤ 32 profiles, ≤ 4 MB; unreadable or newer → read error, never overwritten. |
| Document (`.pmmidi`) | `format` = `org.projectmios.midi-profile`, `version` = 1, `name`, `lines` | ≤ 128 KB; no link, dates or device names. |
| Import report (`MIDIProfileReport`) | counts per `MIDIMappingLineKind`, `unread`, `duplicateOf` | Spoken and shown after import. |
| Line kind (`MIDIMappingLineKind`) | controlChange, noteTrigger, ccButton, realTime, scene, unread | See research MIDI-012-D3. |

State: Save Current / Import add a profile; Rename, Link and Delete edit it; Apply copies its lines to
`settings.midi.mappings` (one Undo step). Erase (FILE-011 Settings) removes the file.
