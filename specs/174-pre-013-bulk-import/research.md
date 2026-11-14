# Research: PRE-013 Bulk Preset Import

## PRE-013-D1: Which ZIP reader

- **Decision**: A new per-entry reader, `LooseZipReader`, in LocalPortability next to `StoredZipReader`,
  sharing its format constants, its bounds-checked byte reader, `CRC32` and `ArchivePath`.
- **Rationale**: `StoredZipReader` (PRE-014, FILE-001/003) is deliberately strict: it refuses the whole
  archive for one unsafe path, one link, one compressed entry or an archive comment, which is right for
  the app's own export format and wrong for ordinary preset packs, where most archives are deflated and
  carry a `__MACOSX` folder. Bulk import needs a verdict per entry (R3, R5). Reusing the structures keeps
  the trust rules (every offset checked before use, CRC verified, names through `ArchivePath`) in one
  place.
- **Alternatives**: loosening `StoredZipReader` (would weaken FILE-003/PRE-014 guarantees); a
  third-party ZIP library (Constitution IX, no new dependency); `NSFileCoordinator`'s `.forUploading`
  zipping (writes only, no reading).

## PRE-013-D2: Deflate

- **Decision**: Inflate with Apple's Compression framework (`compression_decode_buffer`,
  `COMPRESSION_ZLIB`, which is raw DEFLATE as used by ZIP method 8) behind `#if canImport(Compression)`.
  The output buffer is the central directory's uncompressed size plus one byte, never more than the
  512 KiB preset limit plus one, so an archive cannot make it allocate more; the result must have exactly
  the declared size and CRC-32. Without Compression (Linux tests) a deflate entry is "unsupported".
- **Rationale**: public SDK API (Constitution I), no own decompressor to fuzz; the size is decided from
  the central directory before anything is inflated (too large entries are never read).
- **Alternatives**: a Swift inflate implementation (more code to trust and maintain); stored-only
  archives (most real archives would be unsupported).

## PRE-013-D3: Where the pipeline runs

- **Decision**: `BulkPresetImporter` is a nonisolated pipeline started in a detached task: it lists,
  reads, hashes and validates off the main actor and off the library actor; only the batch commit
  (`commitBulk`) runs on the `UserPresetLibrary` actor. Progress values are sent to the main actor.
- **Rationale**: hashing and the validator dominate the cost; doing them outside the actor keeps the
  library (and My Presets' refresh) responsive during the import (R7).

## PRE-013-D4: Batches and cancel

- **Decision**: drafts (files that passed every check) are saved in batches of 50 through
  `UserPresetStore.commitImport` (FILE-003's staged all-or-nothing commit). The cancel check runs before
  each file; on cancel the current batch is saved, then the run ends. Counts of drafts are final only
  after their batch is saved (a failed batch turns its drafts into "failed").
- **Rationale**: per-file atomicity (R8) with far fewer index rewrites than one save per file (1,000
  presets × one `index.json` rewrite each would write hundreds of MB); a crash loses at most the unsaved
  batch and leaves no partial file (R13).

## PRE-013-D5: Duplicate baseline

- **Decision**: at the start the importer takes a baseline from the library (stored SHA-256s, the
  built-in git blob hashes, the takedown list, the shipped texture names); within the run it keeps a
  map SHA-256 → first path. `commitBulk` checks the store again before saving (another change in
  between becomes "duplicate").
- **Rationale**: exact, deterministic counts (S1) without holding the actor for the whole run.

## PRE-013-D6: Bounds

- **Decision**: 2,000 listed files, 64 MiB of candidate `.milk` bytes, 8 folder levels, a 64 MiB
  archive; refusals before anything is read for the first two. A folder walk stops listing after 2,001
  files (so a huge folder is refused quickly). Archive entries whose path has more than
  `ArchivePath.maxComponents` (8) components are "unsupported (too deeply nested)".
- **Rationale**: 2,000 is twice the 1,000-preset library cap; 64 MiB bounds memory for an archive held
  in memory and the read volume of a folder; the per-file limit stays PRE-012's 512 KiB.

## PRE-013-D7: Invalid files are skipped, not quarantined

- **Decision**: see spec Clarifications. The validator's rejection reason is the item's detail.

## PRE-013-D8: Announcements

- **Decision**: library lane; start, the first crossing of 25, 50 and 75 % of the listed files, and the
  summary. The shared announcer's 1 s window coalesces anything faster.
