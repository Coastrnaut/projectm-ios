# Research: MIDI-012 MIDI Mapping Profiles

## MIDI-012-D1: A profile is the stored line list, verbatim

- **Decision**: A profile stores the `settings.midi.mappings` array as it is, not parsed bindings. Save Current reads the
  stored array; Apply writes the profile's array back unchanged.
- **Rationale**: The acceptance asks for byte-identical channels, controls and destination IDs; any parse and
  re-serialize step would reorder lines (the coordinator writes CC, then trigger, then scene lines) and drop lines this
  version cannot read. Comparisons use UTF-8 bytes because Swift `String` equality is canonical-equivalence based.
- **Alternatives**: Parsed bindings per kind (loses unknown lines and order); a second live list per controller
  (conflicts with MIDI-003's single global list).

## MIDI-012-D2: Exported document

- **Decision**: JSON `{"format":"org.projectmios.midi-profile","version":1,"name":…,"lines":[…]}`, sorted keys, pretty
  printed, slashes unescaped, extension `.pmmidi`. Unknown top-level fields are ignored on import; a higher version is
  refused ("made by a newer version").
- **Rationale**: Text that users and other tools can read; JSON string escaping round-trips every Unicode scalar.
- **Alternatives**: Property list (less portable), the plain line list (no name, no version).

## MIDI-012-D3: Line kinds for the report

- `cc:` readable by `MIDIControlBinding` → control change; `pc:` lines and `note:…=cue.go:` → scene (MIDI-007's
  classifier, readable or not counted as scene when readable, else unread); `note:` readable → note trigger; `ccbtn:` →
  CC button; `rt:` → real time; anything else, or an owned line that does not read → unread. The report counts each
  kind and says "<n> lines are not used by this version and are kept as they are."

## MIDI-012-D4: Validation limits

- Import reads at most 128 KB (the file's size is checked before reading; reads stop at the limit).
- At most 512 lines (64 CC + generous room for triggers, scenes and future kinds), at most 256 UTF-8 bytes per line, no
  control characters (Unicode general category Cc) in a line, which also rules out line breaks that would split a line.
- Name: trimmed, control characters removed, at most 60 characters; empty after cleaning → refused ("The file has no
  profile name.").
- Store: at most 32 profiles; the file is at most 4 MB (32 × 512 × 256 bytes is the theoretical maximum before JSON
  overhead).

## MIDI-012-D5: Local store file

- **Decision**: `Application Support/MIDIProfiles/profiles.json`:
  `{"format":"org.projectmios.midi-profiles","version":1,"profiles":[{"id","name","lines","link"?}]}`, written with
  `Data.write(options: .atomic)`. A file that cannot be read (corrupt, newer version, too large) sets a read error: the
  section shows "Saved profiles could not be read." and every write is refused, so the file is never overwritten.
- **Rationale**: Matches the other stores (`PresetCollectionStore`, `ShowStore`); bounded and versioned.

## MIDI-012-D6: Undo as stored-line snapshots

- **Decision**: The coordinator's one-step Undo becomes the stored line array before the change. Undo writes it back
  verbatim and reloads the three lists. Learn, delete and mode edits snapshot `cc + notes + scenes + other`, which equals
  what was stored, so their behaviour is unchanged.
- **Rationale**: Apply must restore the previous list exactly, including order and unread lines.

## MIDI-012-D7: Backup and erase

- **Decision**: FILE-005's library backup does not carry the profiles file; FILE-011's Settings category erases the
  `MIDIProfiles` folder (and counts one item when the file exists).
- **Rationale**: The export is the explicit, portable form; the link is a device identifier ADR-0038 Decision 8 keeps
  out of backups; profiles are MIDI settings like `settings.midi.mappings`, which Settings erases.
- **Alternatives**: Back the file up with links stripped (needs a new backup record kind and restore path; deferred to
  a later row if users ask).

## MIDI-012-D8: Controller link and suggestion

- **Decision**: "Link to <input>" lists listed online inputs with a system unique number (never fallback IDs). While the
  MIDI Mappings screen is open, the first profile (in list order) whose link is listed and whose lines differ from the
  current list is shown as "Suggested for <input name>: <profile>" with Apply. Names come from discovery at display time
  and are never stored.
- **Rationale**: Controller-specific without auto-apply (Apply replaces user data, so it stays a user action).

## MIDI-012-D9: Unread lines survive edits

- **Decision**: `MIDIMappingCoordinator.otherLines` = stored lines that are not a readable `cc:` line, not a trigger
  line and not a scene line; `save()` appends them after the known lines.
- **Rationale**: A profile from a newer version keeps its lines after a learn. Readable `cc:` lines for parameters this
  build cannot drive are still dropped, as MIDI-003 specifies.
