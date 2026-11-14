# ADR-0052: Incremental Folder Backup with a Content-Addressed Media Manifest

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: FILE-006 (`specs/139-file-006-incremental-backup`)
- **Constitution**: I (public APIs), VI (modular boundaries), X (evidence-based quality); Security
  (files from a chosen folder are untrusted) and Privacy
- **Builds on**: ADR-0041 (FILE-005 `.pmbackup`, which leaves videos and imported audio to FILE-006),
  ADR-0043 (FILE-008 content-addressed media store), AUD-001 (content-addressed audio library),
  ADR-0029 (checksums give integrity, not authenticity), ADR-0048 (FILE-011 erase at the next launch)

## Context

The roadmap row asks to "record changed file hashes to avoid recopying unchanged media", with the
acceptance "Second backup identifies unchanged assets without rereading video payload". FILE-005
writes one stored ZIP built in memory: any change rewrites the whole file, and it deliberately holds
no videos or imported audio. An incremental backup therefore needs a destination that can be updated
file by file, and a record of what is already there.

## Decision

1. **Destination**: a folder the user picks ("Back Up to Folder…"). The app writes `projectM Backup/`
   inside it (or uses the picked folder when it already holds a manifest): `projectM Library.pmbackup`
   (the FILE-005 archive, format unchanged, rewritten in full each time; it is small), `media/<sha256>.<ext>`
   (one copy per content) and `backup-manifest.json` (format `org.projectmios.backup-folder`, version 1).
   The single-file "Back Up Library…" is unchanged.
2. **Manifest**: per asset `kind` (open token: `photo`, `video`, `audio`, `audio-index`; other features
   may add kinds), logical `name`, `byteCount`, `modified` (only for files without a content address),
   `sha256` (optional only for older manifests) and `location`; plus the archive's name, size and hash.
   Read with FILE-007 bounds (4 MiB, 8,192 entries); any invalid field makes the whole manifest unusable.
3. **Unchanged without reading**: same key and size, and the same content address (FILE-008 payloads and
   AUD-001 assets are named by their SHA-256) or, for the rest (legacy `<UUID>` copies, the audio index),
   the same modification date; and the copy still exists with that size. Such files are never opened.
   Dates are read only for files in the app container (privacy manifest C617.1); copies in the folder
   are checked by existence and size only.
4. **Copies** are hashed while written (one read), under `.partial-<UUID>`, then renamed to their
   content name. A content-addressed asset whose copy the previous manifest names (or this run wrote)
   is reused by name.
5. **Safety**: copies, then the archive (atomic), then the manifest (atomic), then pruning. A missing,
   damaged or newer manifest means a full backup in which nothing in the folder is trusted. Pruning
   removes only `<sha256>.<ext>` and `.partial-*` names in the backup's own `media/` that the new
   manifest does not name.
6. **Restore** ("Restore Media from Folder…") verifies every copy's size and SHA-256 while staging it in
   `Application Support/MediaRestore/` (any mismatch refuses the whole restore); the next launch, after
   FILE-005's restore and before FILE-008's reconcile, installs photos and videos whose identifier does
   not resolve (as legacy files the migration registers) and imported audio only when the device has no
   audio index. It cannot be requested while a FILE-011 erase waits, and an erase cannot be requested
   while it waits.

## Consequences

- A second backup with no changes reads no media bytes (package acceptance test with an IO-counting
  file access and a 4 MiB fake video; simulator UI test reports "0 copied, 2 unchanged").
- Photos are stored twice in a folder backup (in the archive and in `media/`); at most 64 small files.
- A file modified in place inside the app container with the same size and date would be missed; the
  stores never modify files in place (payloads are immutable, legacy copies are written once).
- Merging two audio libraries is not supported; a device with imported audio keeps its own.

## Alternatives rejected

- An incremental or append-only archive: a container format of our own and a full read to restore.
- Hashing every file on every backup: rereads every video, the cost the row exists to avoid.
- A security-scoped bookmark to the folder: more stored state; the manifest in the folder already makes
  any later backup to it incremental.
- Installing restored media immediately: the audio library actor would overwrite an index written under it.
