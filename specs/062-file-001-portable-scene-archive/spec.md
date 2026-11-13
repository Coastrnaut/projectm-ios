# Feature Specification: FILE-001 Portable Scene Archive

**Feature Branch**: `feature/file-001` (spec directory `062-file-001-portable-scene-archive`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement FILE-001 (Portable scene archive) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Package scene JSON and permitted
local assets in a versioned ZIP." Acceptance, verbatim: "Round-trip on clean install resolves all
relative assets offline." P0, effort L, depends on SCN-001 (versioned scene format)."

Identifiers in this feature carry the roadmap ID: requirements `FILE-001-R1…`, success criteria
`FILE-001-S1…`, tasks `FILE-001-T01…`. Other features' IDs are cited as they are: SCN-001-R6 (assets
by store identifier or embedded), SCN-001-R9 (validation issues), PRE-014-R13/R14 (safe archive
paths, bounded stored ZIP reader), MED-001-R6 and MED-002-R6 (a failed import changes nothing),
MED-014 (structure checks before decoding), SHD-011-R3 (executables and archives refused by their
first bytes).

## Baseline: what exists today (audit of 2026-11-13, commit `241b39b`)

The row's gap status is "Gap candidate". The audit confirms a gap: nothing packs a scene.

| Area | Today | Gap for this row |
|---|---|---|
| Scene document | `SceneFormat` (SCN-001): canonical JSON, validation, live adapters. Photo and video referenced by store UUID; text and generator graphs embedded. Not used by the app yet (SCN-002). | A document alone does not carry its photo or video; on another device the references are missing. |
| Archive code | `LocalPortability` (PRE-014): bounded stored-only ZIP writer and reader (safe relative names, unique ignoring case, entry and size limits, CRC-32), and `PortableArchive` (a `manifest.json` listing every file with SHA-256 and length; unlisted files refused). Used by the user preset export. | No scene archive format. |
| Media stores | `PhotoStore` (MED-001) and `VideoStore` (MED-002): one stored photo and one stored video in Application Support, imported only through the sanitizers (metadata stripped, size caps, MED-014 structure checks). Each import replaces the previous copy after it succeeds. | No way to stage an import without making it current, so a multi-file import cannot be all-or-nothing. |
| Untrusted bytes | SHD-011 recognizes executables, scripts and archives by their first bytes (internal to `GeneratorGraphImport`). | Not reusable by other importers. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What is the archive's container and name? → A: The PRE-014 container: a standard ZIP with every entry stored (no compression), written and read by the app's own bounded code (`LocalPortability`). File extension `pmscene` (type identifier `org.projectmios.scene-archive`, conforming to ZIP archive); the screen row that offers the file to the user declares the type. Reusing one audited reader keeps one attack surface.
- Q: What is inside? → A: Exactly `manifest.json`, `scene.json` (the SCN-001 canonical bytes) and one `assets/<key>.<ext>` file per photo or video asset of the scene (`png`/`jpg` for photos, `mov` for videos). Text overlays and generator graphs stay embedded in `scene.json` (SCN-001). Nothing else: no absolute paths, no file names of the user's originals, no device or account data.
- Q: What does the manifest hold? → A: The PortableArchive header (format `projectm-ios.scene-archive`, format version 1, every other file with its length and SHA-256), the scene file name, and one record per packed asset: key, type (`photo`/`video`) and relative path. The SHA-256 values are written and verified by the existing generic layer; FILE-002 owns the tamper-evidence acceptance (a tampered fixture fails before the library is modified), its report and any archive-level signature.
- Q: Which assets are "permitted"? → A: Only copies already inside the app's own stores (the sanitized photo and video, found by the scene's store UUID). Never a user file outside the stores, never a URL. Export refuses a scene whose photo or video is not on the device (it could not be resolved after import), and a scene with more than one photo or one video asset (the stores hold one of each).
- Q: What does import refuse, and what does it ignore? → A: It refuses whole, with one typed reason, anything not exactly as above: ZIP problems (PRE-014 reader: unsafe or absolute paths, `..`, duplicate names ignoring case, too many entries, oversized entries or archive, compressed or encrypted entries, symbolic links, bad CRC), a missing, malformed, wrong-format or newer manifest, a manifest/scene mismatch, a missing asset file, an extra unlisted file, an asset whose first bytes are an executable, script or archive (SHD-011), an asset whose bytes are not the declared type, and a scene that SCN-001 refuses or reports with errors. Nothing is ignored: a silently skipped file would make "what you imported" differ from "what was sent".
- Q: How are assets imported? → A: Through the same import path as a picked file (MED-001/MED-002 sanitizers with MED-014 checks and the stores' size caps), so an archived photo is re-sanitized exactly like a picked one. Each gets a new store UUID; the scene's asset keys stay, and the photo/video assets' store IDs are replaced by the new ones (the "remapping"). Nothing else in the scene changes.
- Q: What if an import fails part-way? → A: Nothing changes: assets are staged in a temporary folder first, and the stores are changed only after every check passed, in one commit step that moves the staged copies in and then switches the stored identifiers. A failure before the switch removes everything staged; the previous photo and video stay current.
- Q: Does importing replace the user's current photo or video? → A: Yes, because the stores hold one of each (MED-001, MED-002), and only when the archive carries that type: the previous copy is deleted after the commit, exactly as a picked import does. The result says which were replaced, so the screen row (and FILE-003's dry run) can tell the user before confirming. A multi-photo library is a later row.
- Q: Which limits apply? → A: Archive at most 600 MB (the 500 MB video cap, the 40 MB photo cap and the 1 MiB scene, plus headers), checked on the file size before it is read; at most 3 entries besides the manifest (scene, one photo, one video); manifest at most 64 KiB; scene at most 1 MiB (SCN-001); photo entries at most 40 MB; video entries at most 500 MB (the store caps). The bounds are the stores' own so no archive can carry what a picked import would refuse.
- Q: Is there a screen in this row? → A: No. This row delivers the format, a tested export and import service in the app and its tests; the screen that saves the current stack as a scene (SCN-002 captures the live stack) and the Files/Share entry points are later rows (SCN-014 dependency pack UI, FILE-003 dry run, FILE-004 conflicts). Without a screen, no type is declared and no user-visible behavior changes yet.
- Q: Is it networked? → A: No. Export writes a local temporary file that the user hands on; import reads a file the user picked. Nothing is uploaded or fetched (Constitution, privacy policy).
- Q: (clarify pass) May an asset's path inside the archive be chosen freely? → A: No. It is exactly `assets/<key>.<ext>`, where `key` is the scene's asset key (SCN-001 rule: an ASCII letter, then letters and digits) and `ext` is `png` or `jpg` for a photo and `mov` for a video. A record whose path differs, or whose type differs from the scene's asset type, is a manifest/scene mismatch. Keys already exclude `/`, `.` and other path characters, so no asset name can leave `assets/`.
- Q: (clarify pass) Are ZIP entries that are symbolic links read as files? → A: No. The PRE-014 reader is tightened for every archive: an entry whose Unix mode marks a symbolic link (or any type other than a regular file) is refused as unsupported. The app never creates links from archives, but a link entry is never what the app wrote.
- Q: (clarify pass) What name does the exported file get? → A: `projectM-iOS Scene <local date>.pmscene`, like the preset export: no scene name, device or user name in the file name (the scene name is inside, where the user put it). The entries' ZIP dates are the export time; tests pass a fixed date so the bytes are reproducible.
- Q: (clarify pass) Is the photo or video re-encoded on export? → A: No. The stored copy's bytes are packed unchanged (they were sanitized on import; MED-001, MED-002), so export is fast and lossless; import re-sanitizes, which for a sanitized PNG or remuxed movie keeps the pictures.
- Q: (clarify pass) Where do staged files live and when are they removed? → A: In a new folder under the app's temporary directory per import; it is removed when the import ends, whether it succeeded or failed. The export's temporary file is removed when the hand-off ends (the screen row calls the cleanup; the service also clears leftovers from an earlier run before writing a new one).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A scene with its media moves to a clean install intact (Priority: P1) — MVP

A performer has a scene with a photo, a video, a text overlay and a generator graph. They export it
as one archive file and open it on another device (or after reinstalling). The scene appears with
the same layers and settings, and its photo and video are there, without any network.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: Export a fixture scene from stores holding a small photo and video, then import
the archive bytes into new, empty stores in separate temporary folders: every asset reference
resolves, the photo and video decode, and the imported scene equals the original once the photo and
video store IDs are replaced by their new ones.

**Acceptance Scenarios**:

1. **Given** a scene with photo, video, text and generator-graph layers and their media in the stores, **When** it is exported, **Then** the archive holds exactly the manifest, the canonical scene and one file per photo/video asset under `assets/`, with relative names only.
2. **Given** that archive and empty stores, **When** it is imported, **Then** the stores hold the photo and video under new identifiers, the scene validates with no missing assets, and it equals the original after remapping.
3. **Given** a scene with no photo or video, **When** it is exported and imported, **Then** the archive holds only the manifest and scene, and the stores are unchanged.

---

### User Story 2 - A hostile or damaged archive changes nothing (Priority: P1)

A file that claims to be a scene archive is damaged, tries to write outside its folder, hides a
program, is enormous, or contradicts itself. The app refuses it with one readable reason and its
photo and video are exactly as before.

**Why this priority**: Archives come from outside the app (AirDrop, Files, mail); the constitution
requires untrusted input to fail gracefully.

**Independent Test**: A table of hostile archives, each refused with its exact reason, with the
stores' files and identifiers byte-for-byte unchanged afterwards.

**Acceptance Scenarios**:

1. **Given** an archive with `../x`, an absolute name, a symbolic link, a duplicate name, too many entries, an oversized entry, a nested ZIP, a Mach-O program, a manifest/scene mismatch, a missing asset or an extra file, **When** it is imported, **Then** each is refused with its reason and nothing in the stores changes.
2. **Given** an archive whose last asset fails the media checks, **When** it is imported, **Then** the photo staged before it is removed and the stores are unchanged.

### Edge Cases

- The scene references a photo that is not on this device: export refuses with the asset's key.
- The scene has an unused photo asset: it is packed like a used one (SCN-001 keeps it).
- Unknown asset types and unknown fields in the scene: kept verbatim through export and import (SCN-001-R10); an unknown asset type carries no file.
- An archive written by a newer app (format version 2): refused as "made by a newer version".
- Two assets of the same type: export and import refuse (one stored photo, one stored video).
- A ZIP entry marked as a symbolic link: refused by the reader.
- An asset record whose path is not `assets/<key>.<ext>` for its type: refused as a manifest/scene mismatch.
- An asset file whose extension does not match its bytes (a JPEG named `.png`): refused as not the declared type.
- An empty archive, a non-ZIP file, a truncated file: refused by the reader.
- Upper/lower case variants of one name (`assets/A.png` and `assets/a.png`): duplicate, refused.

## Requirements *(mandatory)*

### Functional Requirements

- **FILE-001-R1**: An archive MUST be a stored ZIP read and written by `LocalPortability`, holding `manifest.json`, `scene.json` and one `assets/<key>.<ext>` per photo or video asset, and nothing else.
- **FILE-001-R2**: `manifest.json` MUST carry format `projectm-ios.scene-archive`, format version 1, every other file's relative path, length and SHA-256, the scene file name and one record per packed asset (key, type, path).
- **FILE-001-R3**: `scene.json` MUST be the SCN-001 canonical encoding of the scene, unchanged by export.
- **FILE-001-R4**: Export MUST read media only from the app's stores by the scene's store UUIDs and MUST refuse, with the asset key, a photo or video that is not stored, and a scene with more than one photo or video asset. No absolute path, original file name or device data may enter the archive.
- **FILE-001-R5**: Export MUST write the archive to a temporary file that is removed when the hand-off ends (cancelled or done) and report a write failure as a typed error.
- **FILE-001-R6**: Import MUST check the file size before reading and read through the PRE-014 reader with the limits in Clarifications.
- **FILE-001-R7**: Import MUST refuse whole, with one typed reason and a readable message, each case listed in Clarifications ("What does import refuse").
- **FILE-001-R8**: Import MUST refuse an asset whose first bytes are an executable, script or archive (SHD-011) and one whose bytes are not of its declared type, before any decoder sees it.
- **FILE-001-R9**: Import MUST decode and validate `scene.json` with SCN-001; any decode refusal or validation error refuses the archive. Every photo/video asset of the scene MUST have exactly one manifest record and file, and every record an asset.
- **FILE-001-R10**: Import MUST import each asset through the stores' normal import checks (sanitizer, size caps, MED-014), into a staging folder first.
- **FILE-001-R11**: Import MUST replace the photo/video assets' store IDs with the new store IDs and change nothing else in the scene; the result MUST validate with every reference resolving in the stores.
- **FILE-001-R12**: Import MUST be all-or-nothing: on any failure, the stores' files and identifiers are unchanged and staged files are removed; on success, the previous photo/video (of the imported types only) are deleted after the switch, and the result names which were replaced.
- **FILE-001-R13**: The format code (manifest, paths, content checks, remapping, reading and writing) MUST be plain Swift, read no files, use no network, and build and pass its tests on Linux.
- **FILE-001-R14**: Every asset record's path MUST be exactly `assets/<key>.<ext>` (photo `png`/`jpg`, video `mov`); the PRE-014 reader MUST refuse ZIP entries marked as symbolic links or any non-regular file type.
- **FILE-001-R15**: The exported file MUST be named `projectM-iOS Scene <local date>.pmscene` and its media bytes MUST be the stored copies unchanged.

### Key Entities

- **Scene archive**: the ZIP with manifest, scene and asset files.
- **Archive manifest**: header, file list with checksums, scene file name, asset records.
- **Asset record**: key, type, relative path.
- **Import result**: the remapped scene, the new store identifiers, which stored media were replaced.
- **Archive error**: one typed reason with a readable message.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FILE-001-S1**: The fixture scene (photo, video, text, generator graph) exported and imported into empty stores resolves 100% of its asset references with no network, the photo and video decode, and the scene equals the original after remapping.
- **FILE-001-S2**: Every hostile archive in the table is refused with its exact reason and leaves the stores byte-for-byte unchanged (0 exceptions).
- **FILE-001-S3**: A failure on the last asset leaves the stores unchanged and no staged file behind.
- **FILE-001-S4**: The archive package's tests run in under 1 minute on the Mac and pass on the Linux shape; the app tests for this row each finish within 10 seconds.

## Scope: what later rows add

| Row | Builds on this archive by |
|---|---|
| FILE-002 checksums | Owning the tamper-evidence acceptance and report for the SHA-256 values this row already writes and verifies. |
| FILE-003 dry run | Showing counts, replaced media and refusals before the commit step (the import result and errors are its data). |
| FILE-004 conflict resolver | Skip, rename or replace when the scene ID already exists in a scene library (SCN-002). |
| FILE-005/006 backup | Many scenes and mappings in one file, incremental hashes. |
| FILE-007 schema validator | Deeper semantic checks of imported JSON. |
| FILE-008 deduplication | Storing identical media once (with a multi-item store). |
| SCN-002 | Capturing the live stack as a scene for export. |
| SCN-014 dependency pack | The screen that exports the current scene with its media through Files or Share and the import entry point (declares the `pmscene` type). |

## Assumptions

- One stored photo and one stored video (MED-001, MED-002) stay the store model in this row.
- The archive is read into memory (mapped) after its size check; 600 MB is acceptable as mapped memory.
- Media from the stores are already sanitized; import still re-sanitizes because an archive is untrusted.
- No screen changes in this row; the app tests run on the iOS simulator (decoding uses ImageIO and AVFoundation); the cross-device transfer is a `{device}` task.
