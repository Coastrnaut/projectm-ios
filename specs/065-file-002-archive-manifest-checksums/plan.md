# Implementation Plan: FILE-002 Archive Manifest Checksums

**Branch**: `feature/file-002` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/065-file-002-archive-manifest-checksums/spec.md`

## Summary

Most of the row exists (PRE-014 writes and checks every entry's size and SHA-256; FILE-001 reads scene
archives through it and imports all or nothing). This row proves it and closes the small gaps:

1. **LocalPortability**: a new `PortableArchiveError.invalidRecord(path)` for a malformed digest or a
   negative size (today an unnamed `malformedManifest`); distinct messages for size and checksum
   mismatches; `PortableSHA256.Hasher`, an incremental SHA-256 sharing the one-shot compression
   function (research FILE-002-D3).
2. **SceneArchive** (tests only): `SceneArchiveTamperTests`, the tamper table of FILE-002-S1 against
   `SceneArchiveReader`, and a 4 MiB entry test (S3).
3. **App** (`SceneArchiveService`): an optional step observer (`SceneArchiveImportStep`: verified,
   staged, adopted, made current), nil in the shipping app; `SceneArchiveTamperImportTests` imports
   tampered fixtures into seeded stores and requires zero steps and unchanged stores, and a valid
   import to report "verified" first (S2).
4. **Docs**: ADR-0029 amended (checksums are integrity, not authenticity; no signing; the step
   observer; named record refusals); contract §4 of FILE-001's scene archive contract cross-referenced.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac; Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio)

**Primary Dependencies**: LocalPortability (Foundation only), SceneArchive, the app's PhotoStore and
VideoStore; no new dependency, no CryptoKit (research FILE-002-D4)

**Storage**: the app's stores (unchanged); archives are user-picked files

**Testing**: XCTest with `swift test` for LocalPortability and SceneArchive on the Mac host and the
Linux shape (`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc
-DANALYSIS_NO_ACCELERATE --scratch-path .build/linuxshape`); `projectM-iOSTests` (only the scene
archive test classes) on a dedicated iOS 27.2 simulator

**Target Platform**: iOS 26+ app; iOS 26+ / macOS 15 packages; Linux CI

**Project Type**: Swift packages plus the app's import service

**Performance Goals**: no change to verification cost (CRC-32 and SHA-256 once per entry, in place);
the incremental hasher is as fast as the one-shot path for 64-byte-aligned chunks

**Constraints**: verification before any store step; no new memory proportional to an entry; no
wall-clock assertions; no main-actor mutation in setUp/tearDown

**Scale/Scope**: archive ≤ 600,000,000 bytes, ≤ 3 files plus the manifest (scene); preset archives
use the same layer

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pure Swift and Foundation. Pass. |
| VI Modular boundaries | Generic checks stay in LocalPortability; scene rules in SceneArchive; the ordering seam in the app service. Pass. |
| IX Dependencies | None added (no swift-crypto). Pass. |
| X Evidence | Tamper table, ordering proof and vectors are automated tests; no device claim. Pass. |
| Security: imported files untrusted | Strengthened: named refusals, ordering proven; the honest limit (no authenticity) recorded. Pass. |
| Privacy | No data leaves the device; nothing logged. Pass. |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/065-file-002-archive-manifest-checksums/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/archive-checksums.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/LocalPortability/Sources/LocalPortability/PortableArchive.swift   # invalidRecord, messages
Packages/LocalPortability/Sources/LocalPortability/PortableSHA256.swift    # Hasher
Packages/LocalPortability/Tests/LocalPortabilityTests/PortableArchiveTests.swift
Packages/LocalPortability/Tests/LocalPortabilityTests/PortableSHA256Tests.swift
Packages/SceneArchive/Tests/SceneArchiveTests/SceneArchiveTamperTests.swift  # new
Apps/projectM-iOS/Coordinators/SceneArchiveService.swift                    # step observer
Apps/projectM-iOS/Tests/SceneArchiveTamperImportTests.swift                 # new
docs/adr/0029-scene-archive-format.md                                       # amended
```

**Structure Decision**: existing packages and the existing service; one new test file per layer.

## Complexity Tracking

None.
