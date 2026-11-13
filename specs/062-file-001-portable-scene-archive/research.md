# Research: FILE-001 Portable Scene Archive

## FILE-001-D1 Container: reuse PRE-014

- **Decision**: `PortableArchive` / `PortableArchiveWriter` (stored ZIP + checksummed `manifest.json`), format `projectm-ios.scene-archive`, version 1.
- **Rationale**: one audited, bounded reader (safe paths, unique names ignoring case, entry and size limits, CRC-32, overlap checks, unlisted files refused) instead of a second parser; SHA-256 per file comes free and FILE-002 builds on it.
- **Alternatives**: Apple Archive (`AppleArchive`): not readable on other platforms or by the Linux tests; compressed ZIP: needs a decompressor bounded against ratio bombs and media does not compress; a folder package (`.bundle`): not a single file for AirDrop/Files.

## FILE-001-D2 Symbolic links and non-regular entries

- **Decision**: `StoredZipReader` refuses a central entry whose "made by" host is Unix (3) and whose external attributes' file type is not a regular file (0o100000) or unset, with `unsupported("symbolic links or special files")`.
- **Rationale**: the app writes only regular files; a link entry's data is a target path. Nothing in the app creates links from archives, but refusing them is cheaper than reasoning about every future consumer. Non-Unix hosts carry no link type.
- **Alternatives**: ignore the attribute (current behavior: the data would be read as file bytes): harmless today, surprising later.

## FILE-001-D3 Asset content checks before any decoder

- **Decision**: per asset, first SHD-011's `ExecutableSignature.classify` on the first 64 KiB (made public; programs, scripts, Metal libraries, WebAssembly, ZIP/gzip/xar archives), then the declared type: `png` must sniff as PNG and `jpg` as JPEG (MED-014 `ImageHeaderSniffer`, full structure walk), `mov` must pass `MovieContainerSniffer` (bounded box walk, exactly one `moov`).
- **Rationale**: one list of dangerous signatures for every importer; MED-014 already bounds its walks; a mismatch is reported before ImageIO/AVFoundation sees the bytes. The stores' sanitizers run the same checks again on import, by design.

## FILE-001-D4 Limits

- **Decision**: files besides the manifest ≤ 3; manifest ≤ 64 KiB; per-entry limit `max(40 MB photo cap, 500 MB video cap)` in the ZIP reader, then per type: scene ≤ 1 MiB (SCN-001), photo ≤ `ImageImportLimits.standard.maxFileBytes`, video ≤ `VideoImportLimits.standard.maxFileBytes`; archive ≤ 600 MB, checked on the file size before it is mapped.
- **Rationale**: no archive can carry more than a picked import would accept.

## FILE-001-D5 Staging and commit (atomicity)

- **Decision**: `PhotoStore`/`VideoStore` import becomes `stage(at:)` (sanitize into the store's own folder under a new UUID without touching its identifier) + `makeCurrent(_:)` (set the identifier, then delete the previous copy). The service stages into stores whose folder is a per-import temporary folder, validates the remapped scene against the staged IDs, then commits: move each staged file into the real folder (on any failure, delete the moved ones and stop: nothing current changed), then switch identifiers and delete previous copies. The staging folder is removed in every case.
- **Rationale**: the stores' import path (MED-001/002/014, size caps, metadata stripping) is reused unchanged; the only non-atomic window is the identifier switch, two in-memory `UserDefaults` writes that cannot fail.
- **Alternatives**: scratch `UserDefaults` suites per import (leave plist files behind); importing straight into the real stores and rolling back (the previous copy is deleted by a successful import, so rollback could not restore it).

## FILE-001-D6 Remapping

- **Decision**: `SceneDocument.remappingStoreIDs([assetKey: newStoreID])` replaces the store ID of each photo/video asset named and keeps its `extra` fields; keys, layers and everything else are unchanged. Equality test: `imported == original.remappingStoreIDs(mapping)` and `imported.assets.keys == original.assets.keys`.

## FILE-001-D7 No screen in this row

- **Decision**: no UI, no exported UTType declaration, no DEBUG panel; `SceneArchiveService` with injectable stores and temporary folder, verified by app unit tests on the simulator. The app has no live-stack-to-scene capture yet (SCN-002), so a Settings "export current stack" button would need that adapter first; SCN-014 adds the entry points and declares `org.projectmios.scene-archive` (`pmscene`, conforms to `public.zip-archive`).
- **Rationale**: conservative; no user-visible change until the scene library exists. The service is the seam.

## FILE-001-D8 File name and dates

- **Decision**: `projectM-iOS Scene yyyy-MM-dd.pmscene` (local date, `en_US_POSIX` digits), ZIP dates = export time; tests pass a fixed date and compare bytes of two exports.
