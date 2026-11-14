# Contract: PRE-013 Bulk Preset Import

## C1. Sources (`BulkImportSource`, `LooseZipReader`)

- `BulkImportSource.folder(URL)`: walks the folder under its security scope with
  `contentsOfDirectory` (no enumeration options that follow links). Per entry: name starts with "." or
  equals `__MACOSX` → hidden (counted, not listed); symbolic link → unsupported "a link (not
  followed)"; folder → opened when its depth ≤ 8, else counted as not opened; regular file → listed
  (candidate if its extension is `milk` in any case, else unsupported "not a preset file"); anything
  else → unsupported "not a regular file". Listing stops at `maxFiles + 1` → refusal.
- `BulkImportSource.archive(URL)`: the file must be regular and ≤ 64 MiB; `LooseZipReader.entries`
  lists every central-directory entry, in order: unsafe path (`ArchivePath` rejects it: `..`,
  absolute, backslash, colon, control characters, empty components) → unsupported "outside the archive's
  folder" (checked first, so `../x` is never mistaken for a hidden name; too many components → "too
  deeply nested"); directories are not listed; any path component starting with "." or equal to
  `__MACOSX` → hidden; Unix link or special file → unsupported "a link
  (not followed)"; encrypted → unsupported "encrypted"; method other than 0 and 8 (or 8 without
  Compression) → unsupported "compressed in a way the app does not read"; then candidate or "not a
  preset file" by extension. A structurally unreadable archive (no end record, ZIP64, multiple disks,
  central directory out of bounds) is a refusal.
- `LooseZipReader.data(of:limit:)`: local header checked against the central record and the bounds;
  stored data or inflated data must equal the declared size and CRC-32, else it throws (→ failed
  "damaged in the archive"). Never reads more than `limit + 1` output bytes.
- Refusals before anything is read: more than 2,000 listed files; more than 64 MiB summed over
  candidates within the per-file limit.

## C2. Words

- Summary: "Added 70. Skipped 30: 15 duplicates, 8 invalid, 4 too large, 3 not presets. Failed 0."
  (zero parts of "Skipped" are left out; "Skipped 0." when none).
- Cancelled: "Import cancelled after 30 of 100 files. " + summary + " 70 files were not handled."
- Refused: "Nothing was imported. " + reason.
- Start: "Importing <name>: <N> files." Progress: "<p> percent imported, <n> of <N> files."
- Item details: "Added as “<name>”." · "Same as “<path>” in this import." · "Already in My Presets as
  “<name>”." · "Same as the built-in preset “<name>” (<pack>)." · the validator's reason message ·
  "On the takedown list." · "Empty file." · "Larger than 512 KiB." · "Not a preset file." · etc. ·
  "Could not be read." · "My Presets is full (1,000)." · "Could not be saved."

## C3. Pipeline (`BulkPresetImporter.run`)

```swift
static func run(_ source: BulkImportSource, library: UserPresetLibrary,
                limits: BulkImportLimits = .standard,
                isCancelled: @escaping @Sendable () -> Bool,
                progress: @escaping @Sendable (BulkImportProgress) -> Void) async -> BulkImportReport
```

Per file in path order, before which `isCancelled()` (or task cancellation) is checked: unsupported →
too large (listed size, and the read length) → read (failed) → empty (invalid) → SHA-256 seen in this
run (duplicate) → in the baseline store hashes (duplicate) → git blob hash built in (duplicate) →
takedown (invalid) → validator rejection (invalid) → draft. Every hashed file's SHA-256 is recorded as
seen. Drafts are committed through `UserPresetLibrary.commitBulk` when 50 are waiting, at the end, and
on cancel. `progress` is called after each file with `handled`, `total` and the counts so far.

## C4. App

- `UserPresetsView` shows a "Import Folder or Archive…" button (`bulkImport`), the progress row
  (`bulkImportProgress`, Cancel `bulkImportCancel`) while running, and the summary sheet
  (`bulkImportSummary` text, rows `bulkItem:<path>`, Done `bulkImportDone`).
- `BulkPresetImportCoordinator` announces on the library lane; after the run it runs the waiting trials
  and refreshes My Presets (PRE-002 thumbnails follow the refresh).
- DEBUG: `-uitestBulkImportFolder <path>` starts the import of that folder after the renderer is ready.
