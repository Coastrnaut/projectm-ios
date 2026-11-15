# Research: PRE-017 Preset Restore Points

- **PRE-017-D1 Where versions live.** Decision: `UserPresets/versions/<sha256>.milk`, separate from `files/`.
  Rationale: `files/` holds exactly the live texts (archive install skips writing a text whose file exists;
  FILE-005 and PRE-018 read `files/` by record); a separate folder keeps those rules untouched and makes GC a
  scan of one folder we own. Alternatives: keep old texts in `files/` (mixes live and earlier texts, a live
  import of the same text would share the file and reference counting would span two meanings); embed text in
  JSON (large index, slow saves).
- **PRE-017-D2 Where the list lives.** Decision: sidecar `history.json` (schema 1). Rationale: no
  `index.json` schema bump or migration (existing presets simply have no entry); an unreadable or newer list
  never blocks the presets themselves. Alternative: a field on `UserPreset` (forces an index migration and
  makes FILE-005's record copies carry history).
- **PRE-017-D3 Transaction order.** Decision: write new live text → copy old text to `versions/` (read and
  verified against its SHA-256) → save list → save index (commit) → delete old live text → delete version texts
  no entry names. On index failure the previous list is saved back and every added file removed. A list save
  failure refuses the edit (nothing changed). A crash after the list but before the index leaves a version equal
  to the live text — harmless; a crash before the list leaves an unnamed file, collected at the next load.
- **PRE-017-D4 Bounds.** Decision: 10 per preset (oldest dropped), then globally oldest dropped while
  total entries > 500 or distinct version bytes > 50 MB. Limits injectable for tests.
- **PRE-017-D5 Reference counting.** Decision: a version text is deleted when the set of hashes named by all
  entries (all presets) no longer contains it; deletion only of `<64 hex>.milk` names inside `versions/`.
- **PRE-017-D6 Revert.** Decision: `revert` reads and verifies the version bytes, then calls the same
  internal content-edit routine as `edit` with the current name and `expectedSHA256`; the routine records the
  replaced text as a version. Exact bytes are preserved because the bytes path does not round-trip through
  `String`.
- **PRE-017-D7 Preview.** Decision: read-only text, not a render (PRE-012-R20: only playable stored texts reach
  a renderer; earlier texts are tried by Revert).
- **PRE-017-D8 Backup.** Decision: not backed up. The restore stages a copy of the live folder, so `history.json`
  and `versions/` survive a restore; restored replacements are pending presets with the same ID and keep their list.
