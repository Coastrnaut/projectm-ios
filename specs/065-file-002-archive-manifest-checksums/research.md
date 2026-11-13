# Research: FILE-002 Archive Manifest Checksums

## FILE-002-D1: Where verification happens, in which order

- **Finding** (audit of `a462a64`): `StoredZipReader.read` checks the ZIP structure, then every
  entry's CRC-32 (`StoredZipError.checksumMismatch(path)`); `PortableArchive.read` then checks the
  manifest header, the record list, and per record: safe path, unique, present, size
  (`lengthMismatch`), SHA-256 (`checksumMismatch`); then no unlisted entry. `SceneArchiveReader.read`
  runs all of it before its own checks, and `SceneArchiveService.importArchive` calls the reader before
  it writes anything into staging or the stores.
- **Decision**: keep the order (cheap size before hashing; CRC first catches accidental damage before
  JSON is decoded). Prove the import ordering with a step observer (D2).
- **Consequence for the tamper table**: a changed byte with a stale CRC is refused by the ZIP layer;
  only a byte change with the CRC repaired reaches the SHA-256 check. The table includes both.

## FILE-002-D2: Proving "before import modifies library"

- **Decision**: `SceneArchiveService` takes an optional `@Sendable (SceneArchiveImportStep) -> Void`
  observer, called with `.verified` after the reader accepts, `.staged(path)` per media file,
  `.adopted(type)` and `.madeCurrent(type)` per store. Tests record steps.
- **Rationale**: observes the real code path with the real stores (MED-001/002 sanitizers run);
  combined with the byte-for-byte store snapshot it proves both "no step ran" and "nothing changed".
- **Alternatives**: a store protocol with spy stores (larger refactor of two stores and the service for
  test-only value); file-system snapshots alone (prove no change, not order).

## FILE-002-D3: Large entries and memory

- **Finding**: the service maps the picked copy (`.mappedIfSafe`); the ZIP reader copies each entry
  once into its own `Data` (FILE-001 design: the media are then written to staging); CRC-32 runs over
  the bytes; `PortableSHA256.digestWords` compresses full 64-byte blocks in place and copies only the
  tail (< 64 bytes plus padding).
- **Decision**: no change to the reading path. Verification adds O(1) memory. Add
  `PortableSHA256.Hasher` (fixed-size state: 8 words, a ≤ 64-byte buffer, a length) for chunked use
  (FILE-006, a future file-streaming reader), sharing the compression function so there is one SHA-256.
- **Not measured**: peak memory on a device for a 500 MiB video import (FILE-001's per-entry copy);
  out of this row's scope, noted in the ADR.

## FILE-002-D4: SHA-256 implementation on Linux

- **Finding**: `PortableSHA256` is plain Swift (FIPS 180-4), tested against published vectors, used by
  preset archives and PresetLibrary's `ContentHash`; the packages import no CryptoKit.
- **Decision**: keep it; no swift-crypto dependency (Constitution IX: no new dependency for a solved
  problem). Test the incremental hasher against the one-million-"a" vector
  (`cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0`).

## FILE-002-D5: Authenticity

- **Decision**: out of scope. A manifest digest of itself is impossible; a digest elsewhere in the file
  is rewritable with it. Detecting a forger needs a signature verified with a key the app trusts, and
  the local-first app has no accounts or key distribution. FILE-001's content checks (signatures,
  container sniffing, SCN-001 validation, store sanitizers) still apply to any accepted archive.
