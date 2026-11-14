# Research: FILE-008 User Asset Deduplication

## D1 Reference model for single-slot stores

- **Decision**: A reference is a store identifier (canonical UUID) in the folder's registry. Scenes,
  cues, the autosave, history, settings and archives keep naming identifiers. Making a content current
  keeps the references that share its payload; it releases the previous current reference and every
  reference sharing the previous payload (the old "delete the previous copy"). References with other
  payloads that a FILE-005 restore wrote stay untouched, as their files do today.
- **Rationale**: Keeps MED-001/002 behaviour and privacy (Remove deletes the bytes) while making
  re-imports and archive adoption free and keeping older cues resolvable.
- **Alternatives**: A photo/video library with many current items (out of scope, changes the user
  model); content hashes as identifiers (breaks every stored UUID and the UUID-only validation).

## D2 Payload identity and collision policy

- **Decision**: SHA-256 of the stored (sanitized) bytes, lowercase hex, plus the extension; equal hash
  and equal byte size are identical. Collisions are not considered further.
- **Rationale**: SHA-256 is the project's content hash (AUD-001, PRE-012, FILE-002); a collision is
  computationally infeasible. The size check catches a truncated payload of the same name.
- **Hashing**: streaming, 1 MiB chunks via FileHandle; CryptoKit `SHA256` on Apple platforms,
  `PortableSHA256.Hasher` elsewhere (equal digests; a test checks both paths agree on the host).

## D3 Crash safety without a separate journal

- **Decision**: Each mutation is a sequence of atomic steps whose every intermediate state is valid and
  completed or cleaned by `reconcile`:
  - import: write `.incoming-<UUID>.<ext>` → (payload exists ? delete temp : rename temp to payload) →
    atomic registry write. A crash leaves a temp file or an unreferenced payload; both are removed at
    launch (the import never became current, as today).
  - release: atomic registry write → delete the payload when unreferenced. A crash leaves an
    unreferenced payload; removed at launch.
  - migration of `<UUID>.ext`: hard-link (or copy) to the payload name if absent → atomic registry
    write → the legacy name is removed at the start of the next launch once it is the same file as
    the registered payload. Every step is repeatable; resolution prefers a legacy file, then the
    registry, so the identifier resolves at every point.
- **Rationale**: FILE-004/005 need journals because several folders change together; here the registry
  file is the only multi-entry state and is written atomically, so the folder itself is the journal.
- **Serialization**: one lock per folder path for every mutation and the reconcile.

## D4 Movie header times

- **Decision**: After the passthrough export, `MovieHeaderTimes.zero(fileAt:)` walks the top-level
  atoms to `moov` (bounded: at most 64 MiB moov, 4,096 atoms), and zeroes the creation and modification
  times of `mvhd`, every `tkhd` and every `mdhd` (version 0: 32-bit; version 1: 64-bit) in place.
- **Evidence**: two exports of the fixture movie 2 s apart differed in exactly 6 bytes (the three
  atoms' two times); see the spike in the FILE-008 run log (scratch, 2026-11-14).
- **Alternatives**: hashing the picked source (payload names would not match their bytes); re-encoding
  (MED-002 forbids re-compression).

## D5 Launch reconcile ordering

- **Decision**: In `AppCoordinator.init`, after `LibraryBackupCoordinator.finishPendingRestore`:
  synchronous `prepare()` per folder (remove temp files, remove legacy names that are the same file as
  their registered payload; listing + identifiers, no reads of content), then a detached utility task
  runs `reconcile()` (hash and register legacy files, collect garbage).
- **Rationale**: A restore writes plain files, so reconcile must follow it; hashing a large legacy
  video must not block the first frame (spec Clarifications).

## D6 Backup interplay

- **Decision**: `LibraryContents.readPhotos` lists the folder's logical files (registry references and
  legacy files, legacy wins) as `<UUID>.<ext>` with their bytes. A restore keeps writing plain files
  into the staged folder (which is a copy of the live folder, registry included); the next launch's
  reconcile registers them.
- **Rationale**: The backup format and FILE-005's exactness are unchanged.

## D7 Storage numbers

- **Decision**: The walk already counts payloads once (physical). `ContentAddressedMediaFolder.usage`
  gives logical bytes (sum over references) and physical bytes (sum over payloads); the model adds
  logical − physical of Photos and Videos and the view shows one note when positive.
