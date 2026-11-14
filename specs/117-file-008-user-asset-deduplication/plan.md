# Implementation Plan: FILE-008 User Asset Deduplication

**Branch**: `feature/file-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/117-file-008-user-asset-deduplication/spec.md`

## Summary

A Linux-testable `ContentAddressedMediaFolder` in `Packages/LocalPortability` turns a store folder into
payloads (`<sha256>.<ext>`) plus a registry (`references.json`: store identifier → payload). It interns
a file (streaming SHA-256, size check, reuse or place the payload, add the reference), resolves an
identifier, releases references (deleting a payload when its last reference goes), reports usage
(logical and physical bytes) and reconciles the folder at launch (migrates old `<UUID>.ext` files,
removes temporary files and unreferenced payloads). Every mutation is one atomic file-system step,
serialized per folder, with a fault hook between steps for tests (research D3).

`PhotoStore` and `VideoStore` keep their API and single-slot behaviour but store through the folder:
`stage` writes the sanitized copy to a temporary name and interns it; `adopt` interns a staged copy;
`makeCurrent` keeps references to the same payload and releases the previous content; `remove`
releases the current content. `VideoSanitizer` zeroes the movie-header times so equal sources give
equal copies (`MovieHeaderTimes` in VideoLayer). The app reconciles both folders at launch after the
FILE-005 restore recovery (cheap synchronous clean-up, then hashing on a utility task), counts every
resolving reference as present for scene checks, lets an alias of the current video restore its loop,
reports shared-copy savings on the storage screen, and the FILE-005 reader lists references by their
logical names so backups stay exact.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), Swift 6 language mode; CI also Xcode 26.

**Primary Dependencies**: Foundation (FileManager, FileHandle, URLResourceValues); CryptoKit where it
exists (Apple), `PortableSHA256.Hasher` elsewhere (Linux); AVFoundation unchanged.

**Storage**: `Application Support/Photos` and `Application Support/Videos`: `<sha256>.<ext>` payloads,
`references.json`, temporary `.incoming-<UUID>.<ext>` during an import; legacy `<UUID>.<ext>` until
migrated.

**Testing**: XCTest: LocalPortability and Compositor package tests (host and Linux), LibraryBackup
package tests, app unit tests (PhotoStore, VideoStore, archive import, backup, storage model), an
assertion added to the existing StorageUsage UI test on an own iOS 27.2 simulator.

**Target Platform**: iOS/iPadOS 26.0+. **Project Type**: Mobile app with SwiftPM packages.

**Performance Goals**: Import overhead one streaming read of the stored copy (1 MiB chunks, no
whole-file buffer); launch reconcile without legacy files is a directory listing and one small JSON
read; unit tests about 1-2 s each (owner rule 7).

**Constraints**: Public APIs only, no networking, no new required-reason API (no file dates, no
volume capacity, no `stat`), typed closures, small SwiftUI bodies, no wall-clock assertions, no
main-actor mutation in setUp/tearDown, no C stdio globals.

**Scale/Scope**: Single-slot stores; at most 32 references per payload; FILE-005's 64-photo cap.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: FileManager (`linkItem`, `moveItem`, `removeItem`), FileHandle, URL resource values (file size, resource identifier), CryptoKit |
| VI Modular boundaries | Pass: the folder logic in LocalPortability (Linux-testable), header times in VideoLayer, app stores keep their API |
| IX Pinned dependencies | Pass: no new dependency |
| X Evidence-based quality | Pass: acceptance counts on disk, fault injection at every step, backup round trip, archive import, storage numbers, simulator UI assertion |
| Security | Pass: identifiers stay canonical UUIDs; payload names must be 64 lowercase hex + a known extension; the registry is untrusted input (bounded size, validated entries) |
| Privacy | Pass: local only; Remove still deletes the bytes; video copies lose their import time |

Re-checked after Phase 1 design: unchanged.

## Project Structure

```text
specs/117-file-008-user-asset-deduplication/  plan.md research.md data-model.md quickstart.md contracts/media-store.md tasks.md
docs/adr/00NN-content-addressed-media-store.md   (next free number at commit time)
Packages/LocalPortability/Sources/LocalPortability/ContentAddressedMediaFolder.swift   (new)
Packages/LocalPortability/Sources/LocalPortability/MediaContentHash.swift              (new)
Packages/LocalPortability/Tests/LocalPortabilityTests/ContentAddressedMediaFolderTests.swift (new)
Packages/Compositor/Sources/VideoLayer/MovieHeaderTimes.swift                         (new)
Packages/Compositor/Sources/VideoLayer/VideoSanitizer.swift                           (zero the times)
Packages/Compositor/Tests/…/MovieHeaderTimesTests.swift                                (new)
Packages/LibraryBackup/Sources/LibraryBackup/LibraryContents.swift                    (logical photo names)
Packages/LibraryBackup/Tests/LibraryBackupTests/…                                      (dedup round trip)
Apps/projectM-iOS/Coordinators/PhotoStore.swift, VideoStore.swift                     (through the folder)
Apps/projectM-iOS/Coordinators/SceneArchiveService.swift                              (availability, replaced flags)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                                   (launch reconcile, availability)
Apps/projectM-iOS/Coordinators/VideoCoordinator.swift                                 (alias loop restore)
Apps/projectM-iOS/Coordinators/StorageUsageModel.swift, Views/StorageUsageView.swift  (savings note)
Apps/projectM-iOS/Tests/MediaDeduplicationTests.swift                                 (new)
Apps/projectM-iOS/UITests/StorageUsageUITests.swift                                   (savings note assertion)
```

**Structure Decision**: The folder logic goes into LocalPortability because both the app stores and the
LibraryBackup package (already depending on it) need the layout, and it must run on Linux.

## Complexity Tracking

| Item | Why needed | Simpler alternative rejected because |
|---|---|---|
| Registry instead of hard links as references | Hard-link counts are invisible to the backup reader, the storage walk and folder copies (FILE-003 snapshots, FILE-005 staging), which would double-count or split payloads | Every copier would need link awareness |
| Legacy files kept until the next launch | The running app may hold a legacy file's URL; removing it mid-run would make the layer report a damaged copy | A synchronous full migration would hash a large video on the main thread |
| Zeroed movie-header times | Without it, equal videos never hash equal | Hashing the picked source instead would name payloads by bytes they do not contain |
