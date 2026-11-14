# ADR-0043: A Content-Addressed Store for Imported Photos and Videos, and Its Migration

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: FILE-008 (`specs/117-file-008-user-asset-deduplication`)
- **Constitution**: I (public APIs), VI (modular boundaries), X (evidence-based quality); Privacy
- **Builds on**: MED-001/002 (single-slot photo and video stores, UUID identifiers), MED-003 (loop
  region keyed by the video identifier), AUD-001 (content-addressed audio library), FILE-001 (archive
  import stages, adopts, makes current), FILE-005 / ADR-0041 (library backup lists `photos/<UUID>.ext`)

## Context

Every photo or video import wrote a new copy under a new UUID, even for identical bytes, and the
single-slot stores then deleted the previous copy, so scenes and show cues that named the earlier UUID
reported their media "no longer stored". The roadmap row asks that identical imports be stored once:
"Two identical imports create one physical payload and two references." The remux behind the video
copy also wrote the current time into the movie headers, so equal videos never had equal bytes.

## Decision

1. **Layout** (`ContentAddressedMediaFolder`, LocalPortability): each store folder holds payloads
   `<sha256>.<ext>` (SHA-256 of the stored bytes) and `references.json` (format
   `org.projectmios.media-references`, version 1: an ordered list of `{id: <canonical UUID>, payload}`).
   Identifiers keep their format and meaning everywhere (settings, scenes, cues, autosave, history,
   archives, backups).
2. **Identity and collisions**: equal SHA-256 and equal byte size are identical; collisions are not
   considered further. Hashing streams in 1 MiB chunks (CryptoKit on Apple platforms,
   `PortableSHA256.Hasher` on Linux).
3. **Reference model for single-slot stores**: an import or archive adoption adds a reference (reusing
   an equal payload). Making a content current keeps references sharing its payload and releases the
   previous current reference and every reference sharing its payload; Remove releases every
   reference to the current content. A payload is deleted as soon as its last reference goes. At most
   32 references per payload (the oldest non-current ones are released). References with other
   payloads (photos a FILE-005 restore wrote for scenes) are left alone, as their files were.
4. **Video copies** have zeroed `mvhd`/`tkhd`/`mdhd` creation and modification times
   (`MovieHeaderTimes`), so equal sources give equal copies; this also drops the import time.
5. **Crash safety without a journal**: every mutation is a sequence of single atomic file-system steps
   (rename, hard link or copy, atomic registry write, remove) whose intermediate states are all valid.
   Resolution prefers a legacy `<UUID>.ext`, then the registry. One recursive lock per folder
   serializes mutations.
6. **Migration**: at launch, after the FILE-005 restore recovery, `prepare` (synchronous; no content
   read) removes temporary import files and legacy names that are the same file as their registered
   payload; then `reconcile` (utility task) hard-links (or copies) each remaining legacy copy to its
   payload name and registers it, and deletes unreferenced payloads. A legacy name is removed only at
   the next launch, so no URL the running app holds disappears. Every step is repeatable.
7. **Backups** read photos by their logical names (`logicalFiles`), so `.pmbackup` files are unchanged;
   a restore writes plain files that the next launch migrates.
8. **Storage screen** counts payloads once (the walk sees physical files) and shows "Shared copies of
   identical photos and videos save <size>." when the saving is positive.

## Consequences

- Re-picking the same photo or video, or importing a scene archive that carries media already stored,
  costs no space, and cues saved earlier keep their media; an older reference of the current video
  restores its loop region.
- The launch pass adds one directory listing and one small JSON read per folder; hashing happens on
  imports (already off the main thread) and once per legacy copy.
- Legacy video copies (made before zeroed header times) do not deduplicate against new imports of the
  same movie; the next import of different content releases them as before.
- A damaged registry reads as no references: the folder reads as empty and its payloads are collected
  (the same user-visible result as a missing file today, never another file).

## Alternatives rejected

- **Hard links as references** (no registry): the storage walk, FILE-003 snapshots and FILE-005 staging
  copy or count directory entries, which would double-count or split payloads.
- **Content hashes as identifiers**: breaks every stored UUID and the UUID-only resolution rule
  (MED-001-R14, MED-002-R18).
- **A journal like FILE-004/005**: those change several folders together; here the registry is the only
  multi-entry state and is written atomically.
- **Hashing the picked source instead of the stored copy**: payload names would not describe their
  bytes.
- **A photo/video library**: changes the MED-001/002 user model; out of scope for this row.
