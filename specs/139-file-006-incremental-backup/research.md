# Research: FILE-006 Incremental Backup Manifest

## FILE-006-D1 Destination: a folder, not the archive

- **Decision**: Folder backup `projectM Backup/` (archive + `media/` + manifest). The picked folder is
  used directly when it already holds `backup-manifest.json`.
- **Rationale**: FILE-005's `.pmbackup` is a stored ZIP written in memory and handed to the file mover;
  any change rewrites it. Media in a folder can be skipped file by file. The archive stays
  byte-identical to FILE-005 (format version 1), so "Restore from Backup…" reads it unchanged.
- **Alternatives**: an incremental archive (append-only ZIP) — a container format of our own and a
  full read on restore; media inside the archive — hundreds of MB rebuilt on every backup.

## FILE-006-D2 Change detection without reading

- **Decision**: unchanged = same logical key (kind + name), same size, and either the same content
  address (name-derived) or, for files that are not content-addressed, the same modification date;
  plus the copy named by the previous entry exists with the recorded size. No reads at all.
- **Rationale**: FILE-008 payloads (`<sha256>.<ext>`) and AUD-001 assets are immutable and named by
  content; only legacy `<UUID>.<ext>` copies (until the launch migration) and the audio `index.json`
  need a date. Dates are read only inside the app container (privacy manifest C617.1); the folder's
  copies are checked by existence and size only.
- **Alternatives**: hashing everything (reads every video); trusting names in full-backup mode
  (a damaged folder would be trusted).

## FILE-006-D3 Hash while copying

- **Decision**: every copy streams 1 MiB chunks into a temporary file `media/.partial-<UUID>` while a
  SHA-256 runs (CryptoKit; `PortableSHA256.Hasher` on Linux), then is renamed to `media/<sha256>.<ext>`.
- **Rationale**: one read per new or changed file; the copy's name describes its bytes even when a
  stored name was wrong.

## FILE-006-D4 Crash safety and pruning

- **Decision**: copies → archive (atomic) → manifest (atomic) → prune. Prune deletes only
  `<64 hex>.<ext>` files and `.partial-*` leftovers inside the backup's own `media/` that the new
  manifest does not name.
- **Rationale**: the previous manifest names only files that exist until the new manifest replaces it,
  and nothing is deleted before then. Every name in `media/` follows our pattern, so a leftover from an
  interrupted run is collected next time; nothing outside `media/` is touched.

## FILE-006-D5 Untrusted manifest

- **Decision**: ≤ 4 MiB, FILE-007 bounded JSON, format `org.projectmios.backup-folder`, version 1,
  ≤ 8,192 entries, every field validated (kind token, safe name, `media/<sha>.<ext>` location whose
  stem equals the hash). Any failure: backup treats the folder as new (full backup); restore refuses.
- **Migration**: an entry without `sha256` (an older or hand-made manifest) is not reused; it is hashed
  and copied again. A folder with only a FILE-005 `.pmbackup` gets a full first backup.

## FILE-006-D6 Restore

- **Decision**: verify-and-stage in one read per file (copy into `Application Support/MediaRestore/
  staged/` while hashing; any mismatch refuses and removes the staging), write `request.json` last;
  at the next launch, after FILE-005's restore and before FILE-008's reconcile, install: photos and
  videos as legacy `<UUID>.<ext>` files when the identifier does not resolve (the launch migration then
  registers them), audio assets and the index only when the device has no audio index. Verification
  covers every file (a restore is rare; a sample would let one damaged video through).
- **Alternatives**: installing immediately (the audio actor and media stores are loaded); a security-
  scoped bookmark to read the folder at launch (more state, and the folder may be gone).

## FILE-006-D7 Testing the "not reread" claim

- **Decision**: `BackupFileAccess` is the only path through which media bytes are read; a test wrapper
  counts bytes read per URL. The acceptance test asserts 0 bytes for the 4 MiB fake video and every
  other asset on the second run, 0 copies, and equal manifest entries.
