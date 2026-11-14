# Implementation Plan: FILE-006 Incremental Backup Manifest

**Branch**: `feature/file-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/139-file-006-incremental-backup/spec.md`

## Summary

FILE-005 writes one archive, which must be rebuilt in full every time, so the incremental mode is a
**folder backup**: the user picks a folder; the app writes `projectM Backup/` with the unchanged FILE-005
archive, `media/<sha256>.<ext>` copies and a versioned `backup-manifest.json`. A second backup compares
each media file's size (and, for the few files that are not content-addressed, its modification date)
with the previous manifest and checks the copy is still there; unchanged files are never opened.
FILE-008 payloads and AUD-001 assets are already named by their SHA-256, so their identity comes from
the name. New or changed files are hashed while they are copied (one read). Restore verifies every copy
and installs at the next launch.

New files in `Packages/LibraryBackup` (Linux-testable):

- `BackupFolderManifest.swift`: the manifest, its entries, layout constants and the bounded reader.
- `BackupFileAccess.swift`: the file-reading seam (`status`, `digest`, `copy` with hashing) and its
  local implementation; tests wrap it to count bytes read per file.
- `MediaBackupInventory.swift`: the assets of a library root (photos, videos, audio assets, the audio
  index), with their content address when the stored name carries one.
- `FolderBackupWriter.swift`: the incremental backup (decide, copy, archive, manifest, prune), fault
  hook per step.
- `MediaRestore.swift`: verify and stage from a folder, the request, the launch-time installer and its
  result.

The app adds `FolderBackupCoordinator` (owned by `LibraryBackupCoordinator`), rows in the Backup
section, one folder picker, the launch hook (after the FILE-005 restore, before the FILE-008
reconcile), DEBUG seeds and one UI test.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), Swift 6 language mode; CI also Xcode 26 and Linux.

**Primary Dependencies**: Foundation, SwiftUI, CryptoKit (Apple; guarded, `PortableSHA256.Hasher` on
Linux); local packages LibraryBackup, LocalPortability (`ContentAddressedMediaFolder`,
`MediaContentHash`, `BoundedJSON`).

**Storage**: the chosen folder (`projectM Backup/`); `Application Support/MediaRestore/` (staged
copies, request, last result). No new UserDefaults keys.

**Testing**: XCTest: LibraryBackup package tests (host; Linux in CI), app unit tests, one XCUITest on
the own simulator "FILE6".

**Target Platform**: iOS/iPadOS 26.0+. **Project Type**: Mobile app with SwiftPM packages.

**Performance Goals**: A second unchanged backup reads 0 media bytes; tests use a 4 MiB fake video
(owner rule 7: about 1-2 s per test).

**Constraints**: Public APIs only, no networking, no file dates outside the container (the privacy
manifest declares C617.1 for container files only), typed closures, small SwiftUI bodies, no wall-clock
assertions, no C stdio globals.

**Scale/Scope**: At most 8,192 asset entries; photos ≤ 64, videos and audio as stored.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: FileManager, FileHandle, URL resource values, security-scoped URLs, SwiftUI `fileImporter`, CryptoKit |
| VI Modular boundaries | Pass: format, decision logic, restore in the package; UI, picker and security scope in the app |
| IX Pinned dependencies | Pass: no new dependency |
| X Evidence-based quality | Pass: IO-counting acceptance test, fault injection per step, corrupt/unknown manifests, round trip, simulator UI test |
| Security / Privacy | Pass: the manifest from the folder is untrusted and bounded; paths are validated; restore verifies hashes; prune touches only the backup's own `media/` names; nothing leaves the device except to the chosen folder |

Re-checked after Phase 1 design: unchanged.

## Project Structure

```text
specs/139-file-006-incremental-backup/  plan.md research.md data-model.md quickstart.md contracts/folder-backup.md tasks.md
docs/adr/<next>-incremental-folder-backup.md
Packages/LibraryBackup/Sources/LibraryBackup/BackupFolderManifest.swift      (new)
Packages/LibraryBackup/Sources/LibraryBackup/BackupFileAccess.swift          (new)
Packages/LibraryBackup/Sources/LibraryBackup/MediaBackupInventory.swift      (new)
Packages/LibraryBackup/Sources/LibraryBackup/FolderBackupWriter.swift        (new)
Packages/LibraryBackup/Sources/LibraryBackup/MediaRestore.swift              (new)
Packages/LibraryBackup/Tests/LibraryBackupTests/FolderBackup*Tests.swift     (new)
Apps/projectM-iOS/Coordinators/FolderBackupCoordinator.swift                (new)
Apps/projectM-iOS/Coordinators/LibraryBackupCoordinator.swift               (owns it; launch hook; footer)
Apps/projectM-iOS/Views/LibraryBackupSection.swift                          (rows; folder picker)
Apps/projectM-iOS/Tests/FolderBackupAppTests.swift                          (new)
Apps/projectM-iOS/UITests/FolderBackupUITests.swift                         (new)
docs/privacy-policy.md
```

**Structure Decision**: Inside `LibraryBackup`, beside FILE-005's archive writer and FILE-011's erase,
which share the folder inventory and the launch hook.

## Complexity Tracking

| Item | Why needed | Simpler alternative rejected because |
|---|---|---|
| Folder destination | An archive cannot be appended without rewriting it | Incremental archives would need a container format of our own |
| Restore installed at next launch | The audio library and media stores load at launch; the audio actor would overwrite an index written under it | Installing in place races with the running stores |
