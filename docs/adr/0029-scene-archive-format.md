# ADR-0029: Scene Archive Format, Version 1

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: FILE-001 (`specs/062-file-001-portable-scene-archive`)
- **Constitution**: I (public APIs), VI (modular boundaries), X (evidence); Security (imported files
  are untrusted); Privacy (user media leave the device only by the user's action)
- **Builds on**: PRE-014's `LocalPortability` (stored ZIP, checksummed manifest), ADR-0028 (scene
  document), ADR-0020/0022 and MED-014 (stored photo and video, structure checks), ADR-0024 (user
  content never runs as native code)
- **Number**: the next free number on `autonomous/integration` when written; 0015, 0016, 0025 and
  0026 stay unused.

## Context

FILE-001 asks to "package scene JSON and permitted local assets in a versioned ZIP", accepted when a
"round-trip on clean install resolves all relative assets offline". SCN-001 scenes reference the
photo and video by store UUID, so a scene alone is incomplete on another device. Archives arrive from
outside the app (AirDrop, Files) and must be treated as hostile. The app keeps one stored photo and
one stored video (MED-001, MED-002).

## Decisions

1. **Container.** PRE-014's stored ZIP and `PortableArchive` (every file listed in `manifest.json`
   with length and SHA-256; unlisted files refused). Format `projectm-ios.scene-archive`, version 1,
   extension `pmscene`, type identifier `org.projectmios.scene-archive` (conforms to ZIP; declared by
   the screen row, SCN-014). No compression, no second parser.
2. **Layout.** Exactly `scene.json` (SCN-001 canonical bytes), one `assets/<key>.<ext>` per photo
   (`png`/`jpg`) or video (`mov`) asset, and `manifest.json` (adds `scene` and `assets` records: key,
   type, path). Text and generator graphs stay embedded. Paths are derived from SCN-001 asset keys,
   so they cannot leave `assets/`.
3. **Permitted assets.** Only copies inside the app's stores, found by the scene's store UUIDs,
   packed byte for byte. Export refuses a missing photo/video and more than one of either.
4. **Refusals.** Import refuses whole, with one typed `SceneArchiveError`: size over 600,000,000 bytes
   (checked on the file before reading), every PRE-014 ZIP/manifest problem, symbolic-link and
   special-file entries (the PRE-014 reader now refuses them for every archive), bad or duplicate
   records, a manifest/scene mismatch, missing or extra files, programs, scripts and nested archives
   (SHD-011's signature list, now public), bytes not of the declared type (MED-014 sniffers), and
   any SCN-001 decode refusal or validation error. Nothing is silently ignored.
5. **All or nothing.** `PhotoStore`/`VideoStore` imports split into stage → adopt → make current.
   The service stages media through stores rooted in a per-import temporary folder (the normal
   sanitizers and caps run), remaps the scene's store IDs and validates it against the staged
   copies, then moves the copies in and switches both identifiers. A failure before the switch
   leaves the stores unchanged; the staging folder is removed in every case.
6. **Replacement.** Importing an archive with a photo or video replaces the stored one (the store
   model holds one of each); the result says which were replaced so FILE-003's dry run and the
   screen row can confirm first.
7. **No screen.** `SceneArchiveService` is the seam; SCN-014 adds export/import entry points and the
   type declaration, SCN-002 the live-stack capture. FILE-002 owns the tamper-evidence acceptance
   of the SHA-256 values already written and verified.

## Consequences

- One reader for all app archives; the symlink rule also applies to preset archives.
- The stores' import API grows three small methods; their behavior for picked files is unchanged
  (MED-001/MED-002 tests pass unchanged).
- A multi-photo library (FILE-008, SCN library rows) will need a new store model and a new format
  version only if more than one photo/video per scene becomes possible.

## Amendment 2026-11-13: FILE-002 archive manifest checksums

Decided by Claude under owner rule 4 (`specs/065-file-002-archive-manifest-checksums`, research
FILE-002-D1 to D5). No default is overridden and the format stays version 1.

1. **What the checksums prove.** Every entry except `manifest.json` is listed with its byte count and
   SHA-256 (unchanged). Reading checks every entry's ZIP CRC-32, then per record: safe path,
   well-formed digest and size, unique, present, size, SHA-256; then no unlisted entry. Every
   per-entry refusal names the entry; a malformed digest or negative size is now
   `PortableArchiveError.invalidRecord(path)` instead of the unnamed `malformedManifest`, and size and
   checksum mismatches have distinct messages. The rule applies to preset archives too (same layer).
2. **Integrity, not authenticity.** The manifest cannot carry its own digest, and a digest elsewhere
   in the file can be rewritten with it. A file changed together with its record and its CRC-32 is
   therefore accepted by the checksum layer (FILE-001's content checks, SCN-001 validation and the
   stores' sanitizers still apply). Detecting a deliberate forger needs a signature verified with a
   key the app trusts; the local-first app has no accounts or key distribution and no roadmap row
   asks for it. A test records this limit (`SceneArchiveTamperTests`).
3. **Before the library changes.** `SceneArchiveService` takes an optional step observer (nil in the
   app) reporting `.verified`, `.staged(path)`, `.adopted(type)`, `.madeCurrent(type)`. Tests import
   tampered archives into seeded stores and require zero steps and byte-identical stores; a valid
   import reports `.verified` before every store step.
4. **Memory.** Verification hashes in place over the memory-mapped archive's entry bytes (CRC-32 and
   SHA-256 add O(1) memory). The reader still copies each entry once (Decision 5's staging), so a
   500 MiB video import holds about one copy of the video; not measured on a device.
   `PortableSHA256.Hasher` (incremental, fixed-size state, same compression function) exists for
   file-based hashing later (FILE-006). No CryptoKit: the plain-Swift SHA-256 keeps Linux CI.


## Amendment 2026-11-13: FILE-007 document schema validator

Decided by Claude under owner rule 4 (`specs/068-file-007-document-schema-validator`, research
FILE-007-D1 to D6). No default is overridden and the format stays version 1; no new ADR number.

1. **Manifest shape before decoding.** `manifest.json` is checked by `BoundedJSON` (LocalPortability:
   one forward pass, no recursion, no values built) against the format's declared `DocumentSchema`
   before the platform decoder sees it: strict UTF-8, RFC 8259 grammar, an object at the top, depth,
   string, number and per-container element limits, and no key twice in one object (the platform
   decoder would keep one silently, so two `files` lists could hide an entry). A refusal is
   `PortableArchiveError.manifestRejected(JSONShapeError)` with one of three readable sentences
   (not valid JSON; too large or too deeply nested; the same field twice); the typed reason carries
   the byte offset. Scene archive manifests: 64 KiB, depth 8, strings 4,096 bytes, numbers 32
   characters, 256 elements. Preset archive manifests (same layer): 4 MiB, depth 8, 16,384, 32, 4,096.
2. **Shape first, then version.** The format name and version are read only after the shape check;
   a newer version within the limits is still refused as `newerVersion` ("update the app").
3. **One schema per document.** Each format declares its name, oldest readable and current version
   and limits once (`SceneArchiveFormat.manifestSchema`, `UserPresetArchiveFormat.manifestSchema`,
   `PresetCollectionsFile.schema`, `UserPresetsFile.schema`); readers take both their limits and their
   version verdict from it. The scene document (`scene.json`) keeps SCN-001's own bounded reader
   (1 MiB, depth 32, duplicate keys refused), which is equivalent, and SHD-011's graph import keeps its
   pre-checks (64 KiB, depth 8 before decoding).
