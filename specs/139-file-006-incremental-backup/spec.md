# Feature Specification: FILE-006 Incremental Backup Manifest

**Feature Branch**: `feature/file-006` (spec directory `139-file-006-incremental-backup`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement FILE-006 (Incremental backup manifest) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Record changed file hashes to avoid
recopying unchanged media." Acceptance, verbatim: "Second backup identifies unchanged assets without
rereading video payload." P2, L, depends on FILE-005 (integrated). Verification: schema and fixture
tests plus the simulator."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `FILE-006-R1…`, success criteria `FILE-006-S1…`, tasks `FILE-006-T01…`.

## Baseline (audit of 2026-11-14, commit `e8dde5c0`)

The row's gap status is "Gap candidate". The audit confirms a gap.

| Piece | What exists | What FILE-006 does with it |
|---|---|---|
| FILE-005 backup (`Packages/LibraryBackup`, ADR-0041) | One checksummed archive file (`.pmbackup`, FILE-002 portable archive) built in memory and handed to the system file mover. Holds the show, scenes, current scene, My Presets, collections, settings and photos. Leaves out videos and imported audio, "FILE-006's place". | A single archive must be rebuilt in full every time, so incremental media copying needs a **folder destination**. The archive itself is unchanged (format version 1, same bytes) and is written into the folder beside the media. |
| FILE-008 content-addressed media store (`ContentAddressedMediaFolder`, ADR-0043) | Photos and videos are stored as `<sha256>.<ext>` payloads plus a `references.json` registry (identifier → payload); legacy `<UUID>.<ext>` copies remain until the launch migration. | A payload's name **is** its content hash: its identity is known from the name, with no reading at all. Only legacy copies need hashing. |
| AUD-001 audio library (`AudioLibrary/`) | `index.json` plus `assets/<sha256>.<ext>`, also content-addressed. | Audio assets are backed up by name like payloads; the index is a small file tracked by size and date. |
| FILE-002 `PortableSHA256.Hasher`, FILE-008 `MediaContentHash` | Streaming SHA-256 (CryptoKit on Apple platforms, a portable hasher on Linux). | Reused for hashing and verifying copies in 1 MiB chunks. |
| FILE-011 erase (ADR-0048) | Erases Photos, Videos, AudioLibrary at the next launch. | Untouched; a pending erase blocks requesting a media restore (and the reverse), like FILE-005's restore. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where does an incremental backup go, given that FILE-005 writes one archive file? → A: A folder the user picks with the system folder picker ("Back Up to Folder…"). The app writes `projectM Backup/` inside it (or uses the picked folder directly when it already is one): the FILE-005 archive `projectM Library.pmbackup` (small; rewritten in full each time), a `media/` folder of copies named by content hash, and `backup-manifest.json`. The single-file "Back Up Library…" stays as it is. Trade-off recorded: the archive is re-archived every time (it holds no large media), the media are copied incrementally.
- Q: Which media does the folder backup hold? → A: Every stored photo and video (FILE-008 references, including legacy copies) and the imported audio (AUD-001 assets and its index). Photos are also inside the archive (FILE-005); the duplicate is small (at most 64 photos) and keeps the archive's exact-records restore unchanged.
- Q: What counts as unchanged? → A: An asset whose logical name, size and (for files that are not content-addressed) modification date equal the previous manifest's entry, and whose copy in the backup folder still exists with that size. It is neither read nor copied. A content-addressed file (`<sha256>.<ext>`) is identified by its name alone: it is never hashed during a backup; its copy is reused when one of that name and size is in the folder.
- Q: What happens to copies of assets that were removed from the device? → A: They are pruned after the new manifest is written, but only files the backup itself created: names of the form `<sha256>.<ext>` inside the backup's own `media/` folder that the new manifest does not name. Nothing else in the picked folder is ever touched.
- Q: How does a restore of the media work? → A: "Restore Media from Folder…" reads the folder's manifest, verifies every copy against its recorded hash (all files, not a sample), copies the verified files into the app, and installs them at the next launch before any store loads, like FILE-005's restore. A photo or video is installed only when its identifier is not stored on the device; imported audio only when the device has no imported audio. The library records themselves are restored from the archive with the existing "Restore from Backup…".

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rules 4 and 9).

- Q: What limits apply to the folder manifest read from a user-chosen folder (untrusted)? → A: At most 4 MiB and 8,192 asset entries, bounded JSON (FILE-007 limits), every location must be `media/<64 lowercase hex>.<ext>` with a known extension and every name a safe single path component; anything else reads as "no usable manifest" and gives a full backup (backup) or a refusal (restore) (FILE-006-R5, R8).
- Q: When a new content-addressed asset is copied, is its name trusted as its hash? → A: No: a copy is always hashed while it is written (the only read of that file), and the manifest records the hash of the bytes copied; the copy is named by that hash. Only unchanged assets skip reading (FILE-006-R3, R4).
- Q: What happens in a restore when a photo or video identifier already exists on the device? → A: The device's file stays (it is never overwritten) and the asset counts as "already here"; only identifiers that do not resolve are installed (FILE-006-R8).
- Q: In what order are a backup's files written, and what if one step fails? → A: Media copies first, then the archive, then the manifest (atomic replace), then pruning. Any failure stops the backup with "The backup to the folder did not finish. The previous backup there is unchanged."; leftover temporary copies are removed at the next backup (FILE-006-R6).
- Q: How is progress shown? → A: The existing Working indicator while the backup runs off the main thread; no cancel button (a backup ends when it ends or the app closes, which R6 makes safe); the result line is plain text announced on the `library` lane (FILE-006-R9).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A second backup copies nothing that did not change (Priority: P1)

A user backs up to a folder on their drive: every photo, video and imported track is copied. A week
later they back up to the same folder again without having changed any media: the backup finishes
quickly, reports "3 unchanged", and their large video is neither read nor copied again.

**Why this priority**: It is the row's acceptance.

**Independent Test**: A fixture library holds a multi-megabyte fake video, two photos and an audio
asset. A first backup copies all of them; a second backup with an instrumented file reader reads
0 bytes of the video (and of every unchanged asset), copies nothing, and leaves a manifest with equal
entries.

**Acceptance Scenarios**:

1. **Given** a previous backup in the folder, **When** nothing changed, **Then** the second backup reads 0 bytes from every media file, copies 0 files, and reports every asset as unchanged.
2. **Given** a previous backup, **When** one photo changed, **Then** only that photo is hashed and copied.
3. **Given** a previous backup, **When** one asset was deleted on the device, **Then** its copy is pruned from the folder and its entry dropped.

### User Story 2 - A damaged or interrupted backup is never trusted (Priority: P1)

The manifest in the folder is damaged, comes from a newer app, or the previous backup was interrupted.
The next backup never claims a copy that is not there.

**Independent Test**: A corrupt or unknown-version manifest gives a full backup (every asset hashed and
copied). A fault injected after some copies leaves the previous manifest in place and every file it
names present and correct.

### User Story 3 - Media come back from the folder (Priority: P2)

On a new device the user restores the library from the archive and the media from the folder; scenes
that named a video find it again.

**Independent Test**: Back up a fixture library, restore its media into an empty library root: every
photo and video identifier resolves to the same bytes, the audio library holds the same assets; a
tampered copy refuses the restore and installs nothing.

### User Story 4 - Told what happened (Priority: P2)

After a folder backup the Backup section says "Backed up to the folder: 1 copied, 3 unchanged, 1
removed." and announces it on the `library` lane.

### Edge Cases

- A previous FILE-005-style folder (a `.pmbackup` only) or a manifest whose entries have no hash: treated as a first backup; entries without a hash are hashed again.
- The copy in the folder was deleted or truncated by the user: the asset is copied again (size check).
- Two references share one payload: one copy in `media/`, two manifest entries.
- The folder is read-only or full: the backup fails with a message; the previous manifest stays.
- A restore while a FILE-005 restore or a FILE-011 erase is pending: refused with a note.
- A restore request from a newer app: ignored and removed.
- A manifest entry pointing outside `media/` (a crafted folder): the manifest is unusable; backup does a full pass, restore refuses.
- A photo or video identifier already on the device during a restore: the device's file stays ("already here").

## Requirements *(mandatory)*

### Functional Requirements

- **FILE-006-R1**: The Backup section offers "Back Up to Folder…", which opens the system folder picker and writes the folder backup (archive, media copies, manifest) into the chosen folder.
- **FILE-006-R2**: The folder backup's manifest is versioned (format `org.projectmios.backup-folder`, version 1) and lists one entry per asset: kind (an open string, so other features can add kinds), logical name, size, modification date (only for files that are not content-addressed), SHA-256, and its location in the folder; plus the archive's name, size and SHA-256.
- **FILE-006-R3**: On a backup to a folder that holds a readable manifest, an asset whose entry matches (FILE-006 Clarifications, "unchanged") is neither read nor copied; a content-addressed asset is never hashed; only new or changed assets are read (hashed while copied).
- **FILE-006-R4**: Copies are named by content (`media/<sha256>.<ext>`); one copy serves every asset with that content.
- **FILE-006-R5**: A missing, damaged, oversized or unknown-version manifest gives a full backup (every asset hashed and copied); a manifest entry without a hash is treated as changed.
- **FILE-006-R6**: Writes are crash-safe: each copy is written under a temporary name and renamed; the archive and the manifest are written atomically, the manifest after every copy it names; pruning happens after the manifest. An interrupted backup leaves the previous manifest and every file it names intact.
- **FILE-006-R7**: Pruning deletes only `<sha256>.<ext>` files in the backup's own `media/` folder that the new manifest does not name, and leftover temporary copies; nothing else in the chosen folder.
- **FILE-006-R8**: "Restore Media from Folder…" verifies every copy's size and SHA-256 against the manifest before anything is installed; any mismatch refuses the whole restore, naming the asset. Verified copies are staged in the app and installed at the next launch before the stores read the library: photos and videos whose identifier does not resolve on the device; imported audio only when the device has none.
- **FILE-006-R9**: After a backup the section shows and announces (on the `library` lane) the counts copied, unchanged and removed; after a restore request, the pending state with "Cancel Media Restore"; after the launch-time install, its result once.
- **FILE-006-R10**: No networking, no new permission, public APIs only; files are read only inside the app container and the folder the user picked; the backup reads no file dates outside the app container.
- **FILE-006-R11**: The LibraryBackup package keeps building and testing on Linux.

### Key Entities

- **Folder backup**: the archive, `media/` copies and the manifest inside one folder.
- **Backup folder manifest**: format, version, app version, date, archive record, asset entries.
- **Asset entry**: kind, logical name, size, modification date (optional), SHA-256, location.
- **Media restore request**: the staged, verified copies and their entries, installed at the next launch.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FILE-006-S1**: A second backup of an unchanged fixture library (with a multi-megabyte video) reads 0 bytes from any media file and copies 0 files; its manifest's asset entries equal the first's.
- **FILE-006-S2**: After one photo changes, exactly one file is hashed and copied; after one asset is deleted, exactly its copy is removed.
- **FILE-006-S3**: A corrupt or unknown-version manifest gives a full backup in 100% of cases; a fault at any copy leaves the previous manifest valid with every named file present and matching its hash.
- **FILE-006-S4**: A restore round trip recreates every photo, video and audio asset byte for byte; a tampered copy refuses the restore with nothing installed.
- **FILE-006-S5**: A simulator UI test shows a second folder backup reporting the assets as unchanged, in under 30 seconds.

## Assumptions

- FILE-005's archive writer, folders and launch-time hook; FILE-008's media folder; FILE-002's hasher are the base.
- The user picks the same folder for later backups; the app stores no bookmark (the manifest in the folder is what makes a backup incremental).
- Files in the app's media stores are never modified in place (payloads are immutable, legacy copies are written once); size and date are a sufficient change check for the few files that are not content-addressed.
- Simulator results prove behaviour only, never performance.

## Out of Scope

- Scheduled or automatic backups, backups to a network service, encryption of the folder.
- Incremental archives (the single-file backup stays a full archive).
- Restoring audio into a device that already has imported audio (merging two audio indexes).
