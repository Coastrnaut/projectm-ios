# Research: FILE-009 Storage Usage Explorer

## R1. Which size to sum

- **Decision**: Measure both per regular file: content bytes (`fileSizeKey`) and space used
  (`totalFileAllocatedSizeKey`, falling back to `fileAllocatedSizeKey`, then to content bytes when the
  platform reports no allocation, e.g. Linux). Show space used.
- **Rationale**: Space used is what removal frees and what iPhone Storage reports. Content bytes are
  exact and deterministic, so they carry the exact-match acceptance; space used carries the overhead bound.
- **Overhead bound**: per regular file, `spaceUsed ≤ contentBytes + 4096` (one APFS allocation block).
  Sparse and transparently compressed files may use less; tiny files stored inline may use zero.
  Directories, links and metadata are not counted.
- **Alternatives**: content bytes only (understates real usage for many small files); reading the
  volume block size (needs `statfs`, a DiskSpace required-reason API) — rejected.

## R2. Privacy manifest

- **Decision**: No new required-reason use. Allowed keys: `fileSizeKey`, `totalFileAllocatedSizeKey`,
  `fileAllocatedSizeKey`, `isRegularFileKey`, `isDirectoryKey`, `isSymbolicLinkKey`. Never
  `creationDateKey` / `contentModificationDateKey` (FileTimestamp) or `volume…Capacity…` (DiskSpace).
  Free space is not shown (would need 85F4.1).
- **Check**: `python3 scripts/check_privacy_manifest.py <Debug .app>` scans the app and debug dylib
  symbols.

## R3. Walk safety

- **Decision**: Iterative walk with an explicit stack of (path, depth). Each child path is built by
  appending a listed name to its parent, so the walk never leaves its root except through a link, and
  links (`isSymbolicLink`) are counted as neither file nor folder and never entered. Category roots and
  the container are compared after `resolvingSymlinksInPath().standardizedFileURL` (the device reports
  `/var/…` from some APIs and `/private/var/…` from others); a root that resolves outside the container,
  or that is itself a link, is skipped. Hidden files are counted (they take space).
- **Limits**: depth 32 below a root, 100,000 entries per walk; on reaching one, the walk stops and the
  report is incomplete. An unreadable folder is skipped and marks the report incomplete.
- **Other app data**: one walk of the container that does not descend into any category root.

## R4. Cancellation

- **Decision**: `measure` is synchronous and checks `Task.isCancelled` every 256 entries, throwing
  `CancellationError`. The model runs it in `Task.detached(priority: .utility)`; Refresh and leaving
  the screen cancel the running task; a generation counter drops late results.

## R5. Where the folders come from

- **Decision**: `StorageLocations` names every folder from the stores' own definitions: `PhotoStore`,
  `VideoStore` and `SceneAutosaveStore` `defaultDirectory()`'s folder names, `UserPresetStore` and
  `PresetCollectionStore` `directoryName`, `AudioLibrary.defaultDirectory()`,
  `VideoRecordingCoordinator.defaultDirectory`, `ShareFileStore.defaultDirectory`,
  `SceneArchiveService.exportFolderName`, `UserPresetsCoordinator.defaultExportDirectory`. A test checks
  that `standard()` equals the stores' default directories, so a renamed folder fails the test.
- **SHOW-001** shows: not on this branch; a category is added when it lands (follow-up).

## R6. Deleting

- **Decision**: Nothing is deleted here. FILE-010 owns cache and intermediate cleanup, FILE-011 owns
  erasing user data. Temporary folders are already emptied at launch by REC-003 and REC-012.

## R7. UI test fixture

- **Decision**: DEBUG `-uitestStorageFixture` points `StorageLocations` at
  `<tmp>/StorageFixture/container` (same layout as the real container), recreated at launch with
  known files (Photos 2,000,000 B; Videos 5,000,000 B; Scenes 3 × 10,000 B; Presets 50,000 B; Imported
  audio 3,000,000 B; Recordings 1,000,000 B; Shares 20,000 B; Caches 4,000 B; Other 1,000 B), and shows
  a DEBUG "Add Test Recording" button that writes 2,000,000 B more into Recordings. Real stores are
  never touched by the fixture.
