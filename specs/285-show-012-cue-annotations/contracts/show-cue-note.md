# Contract: cue note in `show.json` (SHOW-012)

- **N1 Write**: a cue with a note has `"note": <string>` (its normalized text); a cue without one has no `note` key. A
  show without notes is byte-identical to before SHOW-012. Format version stays 1.
- **N2 Read**: absent or null → no note. A string → `ShowCueNote.stored`: if the result differs from the string (or is
  empty) the cue gets the result (or no note) and the count goes into `shortenedNotes(n)`. Any other JSON type → no
  note, counted in `droppedNotes(n)`. Never a refusal.
- **N3 Round trip**: decode → encode of a file written by this version is byte-identical; the note string after
  decode equals the one encoded.
- **N4 Privacy**: the note is operator-only. It is never part of a scene document, the HUD, the transport readout, the
  show status text, captions, announcements, OSC send, the external display, recordings, Save Frame, offline export,
  diagnostics or performance reports (spec SHOW-012-R9; `check_compliance.py` SHOW-012-R11).
- **N5 Backup**: FILE-005 carries `show.json` as canonical bytes, so N1-N3 hold through a backup and its exact restore.
