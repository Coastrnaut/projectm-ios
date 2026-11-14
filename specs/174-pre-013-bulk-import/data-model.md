# Data Model: PRE-013 Bulk Preset Import

All values are in memory; nothing new is persisted (R14).

## BulkImportLimits

`maxFiles` 2,000 · `maxTotalBytes` 64 MiB · `maxFolderDepth` 8 · `maxArchiveBytes` 64 MiB ·
`batchSize` 50 · per-file limit `PresetImportLimits.maxFileBytes` (512 KiB).

## BulkImportListing (from a source)

- `sourceName`: the folder's or archive's name (display only).
- `entries`: `[BulkImportEntry]`, sorted by byte-wise path.
- `hiddenCount`: hidden files and folders and `__MACOSX` folders not opened or listed.
- `foldersNotOpened`: folders deeper than `maxFolderDepth`.
- `refusal`: why the whole source is refused (not readable, not a ZIP, over a bound), or nil.

## BulkImportEntry

- `path`: relative path inside the source ("/"-separated).
- `size`: bytes (folder: file size; archive: uncompressed size from the central directory).
- `verdict`: `.candidate` (a regular `.milk` file) or `.unsupported(reason)`.
- reading: folder → the file (regular, not a link, at most the limit + 1 bytes); archive → the entry.

## BulkImportKind (exactly one per handled file)

`added`, `duplicate`, `invalid`, `tooLarge`, `unsupported`, `failed`.

## BulkImportItem

`path`, `kind`, `detail` (one line: the reason, or the added preset's name), `presetID` (added only).

## BulkImportCounts

One count per kind; `handled` = their sum.

## BulkImportReport

`sourceName`, `total` (listed files), `counts`, `notHandled` (= total − handled), `hiddenCount`,
`foldersNotOpened`, `cancelled`, `refusal`, `items` (handled files in path order), `summary` (text).

## BulkPresetDraft (importer → library)

`path`, `fileName`, `contents`, `sha256`, `blobHash`, `warnings`, `licenseLines`. The library turns it
into a `UserPreset` (state `.pending`, PRE-012 naming) or a result: `added(UserPreset)`,
`duplicate(name)`, `libraryFull`, `saveFailed`.

## State of a run (app)

`idle` → `running(progress)` → `finished(report)` (summary sheet) → `idle` when dismissed; Cancel moves
`running` to "cancelling" until the current file and batch end.
