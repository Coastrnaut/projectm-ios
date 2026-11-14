# Implementation Plan: PRE-013 Bulk Preset Import

**Branch**: `feature/pre-013` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/174-pre-013-bulk-import/spec.md`

## Summary

"Import Folder or Archive…" in My Presets imports every `.milk` file of a picked folder or ordinary
`.zip`, off the main thread, with progress, Cancel (atomic per file), duplicate detection by content
hash, and an exact per-outcome report. The logic lives in the packages (Foundation only, Linux-tested);
the app adds one coordinator, one view file and focused wiring.

- **LocalPortability** `LooseZipReader.swift` (new): a per-entry ZIP reader for ordinary archives built
  on the existing `StoredZip` structures (`ZipFormat`, the bounds-checked byte reader, `CRC32`,
  `ArchivePath`). It lists every entry with its own verdict (file, directory, hidden, or unsupported with
  the reason: unsafe path, too deep, link, encryption, method) and reads one entry on demand (stored, or
  deflate through Apple's public Compression framework where it exists; CRC-32 and size verified).
  Research PRE-013-D1, D2.
- **PresetLibrary** `BulkImport/` (new folder):
  - `BulkImportModel.swift`: limits, outcome kinds, items, counts, report, progress, the summary and
    announcement texts (contract C2).
  - `BulkImportSource.swift`: the listing of a folder (manual walk, no symlinks followed, depth and
    count bounds, hidden entries left out) or an archive (`LooseZipReader`), sorted by byte-wise path
    (contract C1).
  - `BulkPresetImporter.swift`: the per-file pipeline (R5 order), batches of 50, cancel check before each
    file, progress after each file (contract C3).
  - `UserPresetLibrary+BulkImport.swift`: `bulkImportBaseline()` and `commitBulk(_:)` on the actor:
    re-checks duplicates and capacity, builds the records as `importFile` does, and saves each batch
    through `UserPresetStore.commitImport` (all or nothing). `UserPresetLibrary`'s `store`, `context`,
    `now`, `makeID` and `loaded()` become module-internal (no behavior change).
- **App**:
  - `Coordinators/BulkPresetImportCoordinator.swift` (new, `@MainActor @Observable`): runs the importer in
    a detached task, publishes progress, Cancel, the report and the library-lane announcements (start,
    quarters, summary), then runs the waiting trials and refreshes My Presets.
  - `Views/BulkPresetImportViews.swift` (new): the "Import Folder or Archive…" row with its own
    `fileImporter` (`.folder`, `.zip`), the progress row with Cancel, and the summary sheet (counts, the
    per-file list, filter "Skipped and failed only").
  - `UserPresetsCoordinator.swift` (focused): owns `bulk`, wires its announcer and after-import refresh;
    single import, archive preview and export are refused while a bulk import runs and vice versa.
  - `UserPresetsView.swift` (focused): the new section and the summary sheet.
  - `AppCoordinator.swift` (DEBUG only, two lines): `-uitestBulkImportFolder <path>` imports that folder
    as if picked (the UI test).
- **ImportFuzz**: one test feeding mutated archives to `LooseZipReader` (no trap, every entry gets a
  verdict).

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/bulk-import.md](contracts/bulk-import.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26 and Linux).

**Primary Dependencies**: LocalPortability, PresetLibrary (existing). No new dependency; Apple's
Compression framework (public, part of the SDK) for deflate, behind `#if canImport(Compression)`.

**Storage**: the existing user preset store (`files/`, `index.json`); no new keys, no new files. The
report is memory only (R14).

**Testing**: XCTest. LocalPortability `LooseZipReaderTests` (stored, deflate on Apple platforms, unsafe
paths, links, encryption, bounds, damage). PresetLibrary `BulkImportAcceptanceTests` (S1 folder, S2
stored and deflate zip, S3 cancel, S4 zip slip, bounds refusals, batch failure) with a generated
100-file fixture in the temporary folder (nothing binary committed). ImportFuzz one test. App:
`BulkPresetImportCoordinatorTests` (announcements, busy rules) and one UI test
`BulkPresetImportUITests` (< 30 s) on simulator "PRE13 iPhone 17" (iOS 27.2).

**Target Platform**: iOS 26+; packages also macOS 15 and Linux.

**Performance Goals**: the 100-file fixture imports in well under the 10 s unit budget on the host;
the main thread only receives progress values.

**Constraints**: type-check budget (300 ms bodies, 200 ms expressions); Linux build of both packages;
`check_status_events.py` covers the new app files; no networking APIs.

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: Foundation, SwiftUI `fileImporter`, Compression (`compression_decode_buffer`). |
| VI. Modular boundaries | Pass: parsing and the pipeline in Foundation-only packages; UI in the app. |
| IX. Pinned dependencies | Pass: none added; the ZIP subset is our own code in LocalPortability. |
| X. Evidence-based quality | Pass: exact-count tests; simulator results are not device evidence; no device task. |
| Security / privacy (untrusted input) | Pass: bounds before reading, no symlinks followed, content-addressed storage behind the store's path guard, zip-slip entries skipped, no file names logged or stored outside the records (R11, R14). |

Re-check after design: unchanged.

## Project Structure

```text
Packages/LocalPortability/Sources/LocalPortability/LooseZipReader.swift            (new)
Packages/LocalPortability/Sources/LocalPortability/StoredZip.swift                 (byte reader internal)
Packages/LocalPortability/Tests/LocalPortabilityTests/LooseZipReaderTests.swift    (new)
Packages/PresetLibrary/Sources/PresetLibrary/BulkImport/*.swift                    (new, 4 files)
Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/UserPresetLibrary.swift   (access levels)
Packages/PresetLibrary/Tests/PresetLibraryTests/BulkImportFixture.swift            (new)
Packages/PresetLibrary/Tests/PresetLibraryTests/BulkImportAcceptanceTests.swift    (new)
Packages/ImportFuzz/Tests/ImportFuzzTests/BulkArchiveFuzzTests.swift               (new)
Apps/projectM-iOS/Coordinators/BulkPresetImportCoordinator.swift                   (new)
Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift                        (focused)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                                (DEBUG launch flag)
Apps/projectM-iOS/Views/BulkPresetImportViews.swift                                (new)
Apps/projectM-iOS/Views/UserPresetsView.swift                                      (focused)
Apps/projectM-iOS/Tests/BulkPresetImportCoordinatorTests.swift                     (new)
Apps/projectM-iOS/UITests/BulkPresetImportUITests.swift                            (new)
scripts/check_status_events.py                                                     (cover new files)
```

## Complexity Tracking

None.
