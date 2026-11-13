# Tasks: FILE-002 Archive Manifest Checksums

**Input**: `specs/065-file-002-archive-manifest-checksums/` (spec, plan, research, data-model, contract,
quickstart)

Budgets (owner rule 7): each unit test about 1-2 s (≤ 10 s), each package suite < 1 minute, app tests
< 30 s each. The app task needs macOS and a simulator (unsigned, own simulator); no device task.

## Phase 1: Foundational — LocalPortability (blocks US1 and US3)

- [ ] FILE-002-T01 Add `PortableArchiveError.invalidRecord(String)` ("The manifest's record for <path> has an invalid size or checksum."), checked per record after the safe-path check (digest "exactly 64 characters `0-9a-f`", size "≥ 0"); distinct messages for `lengthMismatch` ("is not the size its manifest gives") and `checksumMismatch` ("does not match its manifest checksum") in `Packages/LocalPortability/Sources/LocalPortability/PortableArchive.swift` (FILE-002-R3, R4; contract C2)
- [ ] FILE-002-T02 Update `Packages/LocalPortability/Tests/LocalPortabilityTests/PortableArchiveTests.swift`: malformed digest (upper case, 63 and 65 characters, non-hex) and negative size → `invalidRecord(path)`; messages name the entry and differ for size and checksum (FILE-002-R3, R4)
- [ ] FILE-002-T03 [P] Add `PortableSHA256.Hasher` (fixed-size state; `update` with `Data`/`[UInt8]`; `finalize() -> String`) sharing the compression function with `hex(_:)` in `Packages/LocalPortability/Sources/LocalPortability/PortableSHA256.swift` (FILE-002-R6; research D3; contract C5)

## Phase 2: US1 — a tampered archive is refused before anything changes (P1)

**Independent test**: the tamper table against the reader; tampered imports into seeded stores run zero
store steps.

- [ ] FILE-002-T04 [P] [US1] `Packages/SceneArchive/Tests/SceneArchiveTests/SceneArchiveTamperTests.swift`: the tamper table of FILE-002-S1 on the FILE-001 fixture archive, each with its exact `SceneArchiveError`: byte flipped in scene/photo/video with the CRC stale; the same with the CRC repaired; size changed; checksum changed; checksum edited to match a changed file with the CRC stale; manifest bytes edited with the CRC stale; extra entry; renamed entry; malformed digests; negative size; plus the undetectable consistent edit (file + record + CRC) documented as accepted by the checksum layer
- [ ] FILE-002-T05 [US1] `SceneArchiveImportStep` and the optional step observer (`.verified`, `.staged(path)`, `.adopted(type)`, `.madeCurrent(type)`) in `Apps/projectM-iOS/Coordinators/SceneArchiveService.swift` (FILE-002-R5; research D2; contract C3)
- [ ] FILE-002-T06 [US1] `Apps/projectM-iOS/Tests/SceneArchiveTamperImportTests.swift`: a valid export from seeded stores, tampered (video byte with CRC repaired, photo size field, scene checksum, extra entry), imported into seeded target stores: refused with the exact error, zero steps, stores byte-for-byte unchanged, no staging leftovers; a valid import reports `.verified` before every other step (FILE-002-S2)

## Phase 3: US2 — every entry carries its size and checksum (P1)

- [ ] FILE-002-T07 [P] [US2] In `SceneArchiveTamperTests.swift`: every entry of an exported archive except the manifest has exactly one record whose size and SHA-256 (computed independently with the incremental hasher) match the stored bytes (FILE-002-R1)

## Phase 4: US3 — large entries without extra memory (P2)

- [ ] FILE-002-T08 [P] [US3] `Packages/LocalPortability/Tests/LocalPortabilityTests/PortableSHA256Tests.swift`: incremental hashing in chunks of 1, 63, 64, 65 and 4,096 bytes equals the one-shot digest; the one-million-"a" vector (FILE-002-S3)
- [ ] FILE-002-T09 [US3] In `PortableArchiveTests.swift`: a 4 MiB entry verifies; its last byte changed with the CRC repaired is refused as `checksumMismatch` naming it (FILE-002-S3)

## Phase 5: Polish

- [ ] FILE-002-T10 Amend `docs/adr/0029-scene-archive-format.md` (integrity not authenticity, no signing, named record refusals, step observer, memory finding) and cross-reference contract C2 from `specs/062-file-001-portable-scene-archive/contracts/scene-archive.md` §4
- [ ] FILE-002-T11 Verify: `swift test` for LocalPortability and SceneArchive on the host and the Linux shape; PresetLibrary's archive tests (shared layer); `projectM-iOSTests` scene archive classes on a dedicated iOS 27.2 simulator; compliance and docs checks; PosterBoard reports counted before and after (FILE-002-S4, R9)

## Dependencies

T01 → T02, T04, T06, T09; T03 → T07, T08; T05 → T06. US1 is the MVP (the row's acceptance).
Parallel: T03 with T01; T04 with T05; T07, T08 after T03.
