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
