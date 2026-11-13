# Contract: user preset archive and its APIs (PRE-014)

## 1. The file

A ZIP file (APPNOTE subset, research D2):

- every entry stored (method 0), CRC-32 set, compressed size = uncompressed size;
- general-purpose flags: only bit 11 (UTF-8 names); no encryption, no data descriptor;
- no extra fields and no archive comment when written; no ZIP64; single disk;
- entry date and time: the export time in UTC; "made by" Unix 2.0, mode `0644`;
- entries: `presets/<uuid>.milk` sorted by preset id, then `manifest.json`;
- no other entries, no directory entries.

`manifest.json`: [preset-archive-manifest-v1.schema.json](preset-archive-manifest-v1.schema.json),
UTF-8, sorted keys, unescaped slashes, ISO 8601 dates in whole seconds.

Same presets, app version and export time → byte-identical file (PRE-014-R11).

## 2. Limits (reader)

| Limit | Value | Source |
|---|---|---|
| entries | 1,001 | 1,000 presets (`PresetImportLimits.maxUserPresets`) + manifest |
| preset text | 524,288 bytes | `PresetImportLimits.maxFileBytes` |
| manifest | 4,194,304 bytes | `PresetImportLimits.maxIndexBytes` |
| path | 255 UTF-8 bytes, 8 components | research D5 |
| archive | sum of the above plus header overhead | computed by `PortableArchiveLimits` |

## 3. `LocalPortability` API (Foundation only; reusable by FILE-001, FILE-002, PRE-013)

```swift
public enum CRC32 { static func checksum(_ bytes: some Sequence<UInt8>, initial: UInt32 = 0) -> UInt32 }
public enum PortableSHA256 { static func hex(_ bytes: [UInt8]) -> String }
public enum ArchivePath { static func validate(_ path: String) throws -> String   // ArchivePathError
                          static func collisionKey(_ path: String) -> String }
public final class StoredZipWriter {
    init(modified: Date, sink: @escaping (Data) throws -> Void)
    func add(path: String, data: Data) throws          // path validated; duplicates refused
    func finish() throws                               // central directory + end record
}
public struct StoredZipEntry { path: String; data: Data }   // data sliced from the archive
public enum StoredZipReader {
    static func read(_ data: Data, limits: StoredZipLimits) throws -> [StoredZipEntry]  // StoredZipError
}
public struct PortableFileRecord: Codable { path; sha256; byteCount }
public struct PortableArchiveLimits { maxEntries; maxFileBytes; maxManifestBytes; var zip: StoredZipLimits }
public final class PortableArchiveWriter {
    init(modified: Date, sink: @escaping (Data) throws -> Void)
    func add(path: String, data: Data) throws -> PortableFileRecord
    func finish(manifest: Data) throws                 // writes manifest.json, then finishes the ZIP
}
public enum PortableArchive {
    static let manifestPath = "manifest.json"
    static func read(_ data: Data, format: String, supportedVersion: Int, limits: PortableArchiveLimits)
        throws -> PortableArchiveContents              // PortableArchiveError
}
public struct PortableArchiveContents { manifest: Data; files: [String: Data]; records: [PortableFileRecord]; formatVersion: Int }
```

`PortableArchive.read` expects the manifest's top level to carry `format`, `formatVersion` and
`files` (the generic header); other keys belong to the caller.

### Errors and words

| Error | Message |
|---|---|
| `StoredZipError.notAZip` | "This file is not a ZIP archive." |
| `.truncated` | "The archive is incomplete. It may have been cut off." |
| `.unsupported(what)` | "The archive uses <what>, which the app does not read." |
| `.malformed(what)` | "The archive is damaged (<what>)." |
| `.unsafePath(path)` | "The archive names a file outside its own folder: <path>." |
| `.duplicatePath(path)` | "The archive contains <path> more than once." |
| `.tooManyEntries` | "The archive contains more files than the app reads (<n>)." |
| `.entryTooLarge(path)` | "<path> in the archive is larger than allowed." |
| `.archiveTooLarge` | "The archive is larger than the app reads." |
| `.checksumMismatch(path)` | "<path> in the archive is damaged (checksum mismatch)." |
| `PortableArchiveError.missingManifest` | "The archive has no manifest." |
| `.malformedManifest` | "The archive's manifest could not be read." |
| `.wrongFormat` | "This archive was not made by projectM-iOS for this purpose." |
| `.newerVersion(n)` | "This archive was made by a newer version of the app. Update the app to read it." |
| `.unlistedFile(path)` | "<path> in the archive is not listed in its manifest." |
| `.missingFile(path)` | "<path> is listed in the manifest but missing from the archive." |
| `.lengthMismatch(path)`, `.checksumMismatch(path)` | "<path> in the archive does not match its manifest." |

## 4. `PresetLibrary` API

```swift
public enum UserPresetArchiveFormat { static let name = "org.projectmios.user-presets"; static let version = 1
                                      static var limits: PortableArchiveLimits }
public struct ExportedUserPreset: Codable, Equatable { … see data-model.md …
    init(_ preset: UserPreset); func userPreset(state: UserPresetState = .pending) -> UserPreset }
public struct UserPresetArchiveManifest: Codable, Equatable { format; formatVersion; appVersion; exportedAt; files; presets }
public struct UserPresetArchive: Equatable { manifest; texts: [String: Data] }   // keyed by preset id
public enum UserPresetArchiveReader { static func read(_ data: Data) throws -> UserPresetArchive }  // UserPresetArchiveError
public enum UserPresetArchiveWriter {
    static func write(_ items: [(UserPreset, Data)], appVersion: String, exportedAt: Date,
                      sink: @escaping (Data) throws -> Void) throws
}
public struct UserPresetExportPlan: Equatable { exportable: [UserPreset]; excluded: [UserPresetExportExclusion: Int] }
public struct UserPresetExportSummary: Equatable { exported: Int; excluded: …; fileName: String; message: String }
extension UserPresetLibrary {
    func exportPlan() -> UserPresetExportPlan
    func export(ids: [String], appVersion: String, exportedAt: Date, to url: URL)
        -> Result<UserPresetExportSummary, UserPresetExportError>
}
```

`UserPresetArchiveError` cases and words: `archive(PortableArchiveError)` (its message),
`tooManyPresets`, `invalidPreset(id)` "A preset in the archive is not valid (<id>).",
`duplicatePreset(id)`, `pathMismatch(id)`, `contentMismatch(id)` "The text of <id> does not
match its manifest.", `fullLibraryCopy(id)` "The archive contains a copy of a preset from the
full library, which cannot be exported or imported.", `rightsClaimed(id)`.

Export rules (ADR-0008): `exportPlan` lists only playable, not held presets that are imported or
copies of Included presets; `export(ids:)` re-applies the plan, so an id that is not exportable
is counted, never written.

## 5. App

- My Presets toolbar: "Export…" (`exportPresets`), disabled while importing, duplicating,
  exporting, or when the record is from a newer version.
- Export sheet (`presetExportSheet`): rows `exportRow:<name>` (toggle, label "<name>, selected" /
  "not selected"), `exportSelectAll`, `exportSelectNone`, `exportCount`, footer
  `exportExclusions`, button `exportConfirm`, summary `exportSummary`, `Cancel`.
- After writing: summary shown and announced; share sheet opened with the file only; on close
  (any result) the export folder is deleted.
- DEBUG only: `-uitestExportPresetTo <path>` copies the archive to `<path>` before sharing.
