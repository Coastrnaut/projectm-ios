# Feature Specification: FILE-002 Archive Manifest Checksums

**Feature Branch**: `feature/file-002` (spec directory `065-file-002-archive-manifest-checksums`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (FILE-002-T01-T11 verified on the Mac host, the Linux shape and an iOS 27.2 simulator; no device task)

**Input**: User description: "Implement FILE-002 (Archive manifest checksums) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Include SHA-256 checksums and sizes
for each archive entry." Acceptance, verbatim: "Tampered fixture fails validation before import modifies
library." P0, effort M, depends on FILE-001 (portable scene archive)."

Identifiers in this feature carry the roadmap ID: requirements `FILE-002-R1…`, success criteria
`FILE-002-S1…`, tasks `FILE-002-T01…`. Other features' IDs are cited as they are: PRE-014 (the generic
checksummed archive layer), FILE-001-R4 to R12 (scene archive reading and the all-or-nothing import),
FILE-003 (import dry run), FILE-006 (incremental backup hashes).

## Baseline: what exists today (audit of 2026-11-13, commit `a462a64`)

The row's gap status is "Gap candidate". PRE-014 and FILE-001 already write and check most of it; the
gaps are proof, naming and the honest limit.

| Area | Today (PRE-014 `PortableArchive`, FILE-001 `SceneArchiveReader`, app `SceneArchiveService`) | Gap for this row |
|---|---|---|
| Sizes and SHA-256 written | Every file except `manifest.json` is listed in the manifest with its path, byte count and lowercase SHA-256 (scene archives and preset archives). | None. |
| Sizes and SHA-256 checked | Reading checks every entry's ZIP CRC-32, then each listed file's byte count, then its SHA-256; missing, unlisted and duplicate entries are refused. | A tamper table proving each kind of change is caught, with the exact refusal. |
| Malformed record | A digest that is not 64 lowercase hex characters, or a negative size, refuses the archive as "manifest could not be read", without naming the entry. | The refusal names the entry. |
| Before the library changes | The service reads and verifies the whole archive before staging; one app test shows a hostile archive (a program as the video) leaves the stores byte-for-byte unchanged. | Proof that a checksum or size mismatch stops the import before any stage, adopt or make-current step, observed step by step. |
| Large entries | The archive file is memory-mapped; CRC-32 and SHA-256 run over each entry's bytes in place (no second copy; the SHA-256 copies only the last partial block). Each entry is copied once out of the archive, as FILE-001 designed. | A recorded decision and a multi-megabyte entry test; an incremental hasher for later file-based hashing (FILE-006). |
| Linux | SHA-256 is plain Swift (no CryptoKit), so the packages build and test on Linux. | None; kept. |
| Tampering with a file and its record together | Undetected: the manifest cannot carry its own digest, and nothing signs it. | Recorded honestly as out of scope. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Should the archive carry a digest of the manifest itself, or a signature? → A: Neither. The manifest cannot list its own digest, and a digest stored anywhere else in the same file can be rewritten with it; the ZIP CRC-32 of `manifest.json` already catches accidental damage. Authenticity needs a signature and a key the app trusts, which no roadmap row covers and which a local-first app with no accounts cannot distribute. Recorded as a known limit in ADR-0029 (amended) and the format stays version 1.
- Q: How do tests prove that verification happens before the library changes? → A: The import service gains an optional step observer (nil in the app) that reports "verified", then each "staged", "adopted" and "made current" step in order. Tests import every tampered fixture with seeded stores and require zero steps plus byte-identical stores; a valid import must report "verified" before any other step. No store protocol is introduced (smallest change; the real stores stay under test).
- Q: Should a malformed digest or size keep the generic "manifest could not be read" refusal? → A: No. A new refusal names the entry ("The manifest's record for X has an invalid size or checksum."), so every per-entry refusal names its entry (R3, R4). The size and checksum mismatches also get distinct messages ("is not the size its manifest gives" / "does not match its manifest checksum").
- Q: Should verification stream entries from the file in chunks instead of reading them into memory? → A: No change to the reading path in this row. The archive is memory-mapped, CRC-32 and SHA-256 run in place over each entry (the SHA-256 copies at most the last 64-byte block), and the one copy per entry is FILE-001's design, bounded by the 500 MiB video limit. An incremental SHA-256 (chunks in, digest out, fixed-size state) is added and tested so file-based hashing (FILE-006, a future streaming reader) has one implementation.
- Q: Is CryptoKit used for SHA-256? → A: No. The archive packages keep the plain-Swift SHA-256 that already serves preset archives and is tested against published vectors, so the packages build and test on Linux; the incremental hasher shares its compression function.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A damaged or altered archive is refused before anything changes (Priority: P1)

A performer imports a scene archive that was corrupted in transfer or altered by hand (a byte changed in
the scene, the photo or the video; a size or checksum edited in the manifest; a file added, removed or
renamed). The import is refused with a message naming the file, and the stored photo, video and their
identifiers are exactly as they were.

**Why this priority**: This is the row's acceptance: "Tampered fixture fails validation before import
modifies library."

**Independent Test**: Export a valid fixture archive, apply each tampering in the table, import it into
seeded stores, and check the refusal, that no store step ran, and that the stores are unchanged.

**Acceptance Scenarios**:

1. **Given** a valid archive with one byte changed in `scene.json`, the photo or the video, **When** it
   is imported, **Then** it is refused naming that file and no store step runs.
2. **Given** a valid archive whose manifest gives a file the wrong size or the wrong checksum, **When**
   it is imported, **Then** it is refused naming that file and the stores are unchanged.
3. **Given** a valid archive, **When** it is imported, **Then** verification is reported complete before
   the first media file is staged (the positive control for the ordering).

### User Story 2 - Every archive entry carries its size and checksum (Priority: P1)

Any archive the app writes (scene or preset) lists every file it contains with its exact size and
SHA-256, so any later reader, including another device or a person with standard tools, can check it.

**Why this priority**: The row's observable behavior.

**Independent Test**: Write an archive, list its manifest records, and compare each to the size and an
independently computed SHA-256 of the stored bytes.

**Acceptance Scenarios**:

1. **Given** an exported scene archive, **When** its manifest is read, **Then** every entry except the
   manifest has a record whose size and SHA-256 match the entry's bytes, and no record is missing.

### User Story 3 - Large videos are checked without extra memory (Priority: P2)

A scene with a long video (up to the 500 MiB video limit) is verified without a second in-memory copy of
the video for hashing.

**Why this priority**: Verification must not make a valid import fail on a phone for memory reasons.

**Independent Test**: Verify a multi-megabyte synthetic entry and hash it incrementally in small chunks;
the digests equal the one-shot digest and a published test vector.

**Acceptance Scenarios**:

1. **Given** a 4 MiB entry, **When** it is verified, **Then** it is accepted, and with its last byte
   changed (and its ZIP CRC repaired) it is refused as a checksum mismatch naming the entry.

### Edge Cases

- A changed byte with the ZIP CRC-32 left stale: refused by the ZIP layer (checksum mismatch, named).
- A changed byte with the CRC-32 recomputed but the manifest left stale: refused by the SHA-256 check.
- A manifest checksum edited to match a changed file but the CRC-32 left stale: refused by the ZIP layer.
- The manifest itself edited (its CRC-32 stale): refused by the ZIP layer, naming `manifest.json`.
- A size field changed alone: refused as a size mismatch before any hashing.
- An extra entry: refused as unlisted. An entry renamed: refused as missing (the listed name is absent).
- A digest in upper case, of the wrong length, or not hex; a negative size: refused, naming the entry.
- A file, its manifest record and its CRC-32 all changed consistently: accepted by the checksum layer
  (no signature exists); the content checks of FILE-001 still apply. Recorded as a known limit.
- An empty entry: its size is 0 and its digest is the SHA-256 of no bytes.

## Requirements *(mandatory)*

### Functional Requirements

- **FILE-002-R1**: Every archive entry except `manifest.json` is listed in the manifest with its path,
  exact byte count and SHA-256 as 64 lowercase hexadecimal characters (already true; kept).
- **FILE-002-R2**: Reading verifies, for every entry, the ZIP CRC-32, then the listed size, then the
  SHA-256; missing, unlisted and duplicate entries are refused; any failure refuses the whole archive.
- **FILE-002-R3**: Each refusal from R2 names the entry it concerns, in a readable message; a size
  mismatch and a checksum mismatch have distinct messages.
- **FILE-002-R4**: A manifest record whose digest is not 64 lowercase hexadecimal characters, or whose
  size is negative, is refused with its own error naming the entry.
- **FILE-002-R5**: Import verifies the whole archive (R2, R4 and FILE-001's other checks) before the
  first media file is staged, adopted into a store or made current; when verification fails, none of
  these steps runs and the stores' files and identifiers are byte-for-byte unchanged. The import
  reports each step to an optional observer (absent in the shipping app) so tests can see the order.
- **FILE-002-R6**: Verification adds no memory proportional to an entry's size beyond the entry's own
  bytes (hashing runs in place over the bytes); an incremental SHA-256 (feed chunks, then finish) gives
  the same digest as the one-shot function, for later file-based hashing.
- **FILE-002-R7**: Checksums detect accidental corruption and edits that do not also rewrite the
  manifest. They do not authenticate the archive: a consistent edit of a file, its record and its CRC-32
  is not detected. Signing is out of scope for this row; the limit is recorded in the format's ADR.
- **FILE-002-R8**: The archive format version is unchanged (version 1 already carries sizes and
  checksums); no change to what export writes.
- **FILE-002-R9**: Plain code with no CryptoKit dependency in the archive packages, tested on every CI
  host including Linux.

### Key Entities

- **File record**: an entry's path, byte count and SHA-256 in the manifest.
- **Tamper case**: a named change to a valid fixture archive and the exact refusal it must produce.
- **Import step**: verified, staged (per file), adopted (per store), made current (per store); observed
  in order by tests.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FILE-002-S1**: Every case in the tamper table (at least 12 cases, covering scene, photo and video
  bytes, sizes, digests, CRC combinations, manifest edits, extra, missing and renamed entries, and
  malformed digests) is refused with its exact expected error naming the entry (100%).
- **FILE-002-S2**: For every tampered archive imported through the app's import path, zero store steps
  run and the stores are byte-for-byte unchanged; for a valid archive, "verified" precedes every store
  step.
- **FILE-002-S3**: A 4 MiB entry verifies and its one-byte tamper is refused; incremental hashing in
  chunks of 1, 63, 64, 65 and 4,096 bytes equals the one-shot digest and the published one-million-"a"
  test vector.
- **FILE-002-S4**: Each unit test runs in under 2 s and each touched package suite in under 1 minute,
  on the Mac host and the Linux shape; the app tests touched run in under 30 s each.

## Assumptions

- The threat is corruption and casual editing of a file the user picked; a deliberate forger who
  rewrites the manifest is out of scope until a signing row exists (none in the roadmap today).
- The per-entry copy made when reading the archive is FILE-001's design and stays; peak memory for the
  largest video is about one copy of the video plus the mapped file.
- Preset archives (PRE-014) share the same layer and get the same checks and named refusals.

## Scope

| In this row | Later rows |
|---|---|
| Tamper table, named refusals, ordering proof, incremental SHA-256, recorded limit | FILE-003 dry run shows the verified contents before confirming |
| | FILE-006 hashes stored files incrementally for backups |
| | Signing or authenticated archives (no roadmap row yet) |
