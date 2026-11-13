# Research: PRE-014 Bulk preset export

All decisions taken 2026-11-12 under the owner's best-judgement rule (CLAUDE.md rule 4).

## D1. Where the container code lives

- **Decision**: a new Foundation-only package `Packages/LocalPortability`, the name the roadmap's
  proposed layout uses. `PresetLibrary` depends on it. SHA-256 moves there; `ContentHash.sha256Hex`
  keeps its signature and delegates, so no SHA-256 code is duplicated (the roadmap forbids
  reimplementing existing functions under new names).
- **Rationale**: FILE-001 (scene archives), FILE-002 (checksums), FILE-005 (backup) and PRE-013
  need the same container without the preset library (R16).
- **Alternatives**: a `Portability/` folder in `PresetLibrary` (rejected: wrong dependency
  direction for scene archives); duplicating SHA-256 (rejected).
- **Wiring**: `project.yml` lists the package; every package loop in `ios-ci.yml` (Linux, macOS
  host, generic iOS compile, both simulator loops) gains `LocalPortability`.

## D2. Container format

- **Decision**: ZIP (APPNOTE 6.3.x subset), every entry method 0 (stored), general-purpose flag
  bit 11 (UTF-8 names) only, no data descriptors, no extra fields, no comment, no ZIP64,
  version needed 2.0, "made by" Unix 2.0 with mode 0644 so extracted files are readable.
- **Rationale**: the roadmap names ZIP; Foundation has no public ZIP writer on iOS; presets are
  small text, so compression buys little and costs a decompressor (attack surface). Stored ZIP is
  ~200 lines with CRC-32 and opens everywhere.
- **Alternatives**: Apple Archive (`AppleArchive` framework, public on iOS 14+): not readable on
  Linux or by standard unzip tools, and the Linux tests could not exercise it. A plain folder via
  the share sheet: cannot be shared as one item to Mail or AirDrop reliably and has no single
  checksum list. Deflate via `Compression` (`COMPRESSION_ZLIB` is raw deflate): possible later;
  the reader refuses compressed entries for now (PRE-013 may extend).

## D3. Determinism

- Entries sorted by preset id; manifest last (written after the texts so each text is read once).
- Every entry's DOS date and time is the export time in UTC (2-second resolution; years clamped
  to 1980-2107).
- JSON with sorted keys, no slash escaping, ISO 8601 dates in whole seconds (the store record's
  own precision).
- Golden test: fixed ids, dates and app version → a fixed SHA-256 of the archive bytes.

## D4. Reader bounds and order of checks

1. Size: at least 22 bytes, at most `maxArchiveBytes`.
2. End record exactly at the end (comment length 0), single disk, entry counts equal,
   count ≤ `maxEntries`, central directory inside the data and ending at the end record.
3. Per central header: signature, flags ⊆ {bit 11}, method 0, sizes equal and not 0xFFFFFFFF,
   size ≤ the per-entry limit, name 1-255 bytes, valid UTF-8, safe path; header fully inside the
   central directory.
4. Per local header: signature, same flags, method, CRC, sizes and name; data range inside the
   data before the central directory; ranges sorted do not overlap.
5. CRC-32 of each entry's bytes.
6. Archive layer: `manifest.json` present and ≤ 4 MiB; JSON header decodes; format equals; version
   ≤ supported (newer → `newerVersion`); every listed file present with equal length and SHA-256;
   no entry unlisted; listed paths unique and safe.
7. Preset layer: presets ≤ 1,000; each record well-formed (PRE-012/PRE-015 rules); path equals
   `presets/<uuid>.milk` for its id and is in the file list with the same SHA-256 and length;
   git blob hash matches; ids and texts unique; origin rules (ADR-0008); `rightsVerified` false.

## D5. Path rules (`ArchivePath`)

Relative, `/` separators, 1-255 UTF-8 bytes, at most 8 components, no empty, `.` or `..`
component, no leading `/`, no `\`, no `:`, no control or format characters, no trailing `/` for
files. Duplicates are compared after Unicode case folding (macOS and iOS volumes are
case-insensitive) and NFC normalization.

## D6. Share sheet and temporary files

- `UIActivityViewController` with the file URL, presented from a zero-size representable
  controller (popover anchored to it on iPad). `completionWithItemsHandler` fires on completion
  and cancellation; the coordinator deletes the export folder then.
- `.fileExporter` was rejected as the only path: it offers Files alone; the share sheet includes
  "Save to Files" plus the user's own choices. `ShareLink` was rejected: it gives no completion
  callback, so the temporary file could not be deleted.

## D7. Test hook for the UI test

`-uitestExportPresetTo <path>` (compiled only under `DEBUG`): after writing, the coordinator
copies the archive to that host path (the simulator shares the host file system), and the UI
test reads it (stored entries are plain bytes: the test finds `PK\u{3}\u{4}`, `manifest.json`
and the preset name). The same pattern as PRE-012's `-uitestImportPreset`.

## D8. What the manifest leaves out

Check state (pending, playable, proven), quarantine reasons, the store's file names, and any
entitlement or purchase data. The importer (PRE-013) re-validates and re-tries every text.
