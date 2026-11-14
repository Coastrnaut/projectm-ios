# Feature Specification: SCN-014 Scene Dependency Pack

**Feature Branch**: `feature/scn-014` (spec directory `187-scn-014-dependency-pack`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (SCN-014-T01-T10 verified on the Mac: SceneArchive package tests on the host and
the feature's iOS 27.2 simulator "SCN14 iPhone 17"; no device claim). SceneArchive 36 tests (0.3 s; 7 new), app
ScenePackAcceptanceTests 6 (0.29 s), ScenePackUITests 1 (22.1 s, 14.6 s). Linux: not run here; the package's
Linux-shape build (`-D*_NO_*`) passes and the new code is Foundation-only.

**Input**: Roadmap row SCN-014 (P1, size L, depends on SCN-001, integrated). Observable behavior,
verbatim: "Export scene with permitted user media and relative paths." Acceptance, verbatim: "Reimport
offline reproduces scene without absolute filesystem paths."

Identifiers carry the roadmap ID: requirements `SCN-014-R1…`, success criteria `SCN-014-S1…`, tasks
`SCN-014-T01…`, research decisions `SCN-014-D1…`. Other features are cited by their own IDs: SCN-001
(scene document), SHOW-001 (show and cues), SCN-004 (scene folders), SCN-012 (repair report), FILE-001/002
(scene archive and its checksums), FILE-003 (import dry run), FILE-004 (scene import conflicts), FILE-008
(content-addressed media folders), MED-001/002 (photo and video copies), MED-006 (slideshow), MED-010
(logo), MED-013 (media relinking), ACC-004 (announcer lanes).

## Baseline: what exists today (audit of 2026-11-14, commit `2a895211`)

| Area | Today |
|---|---|
| Scene archive (FILE-001/002) | `.pmscene` = a stored ZIP with `manifest.json` (every file's length and SHA-256), the canonical `scene.json` and one `assets/<key>.<ext>` per photo, video and logo (MED-010). Entry names pass PRE-014's `ArchivePath` rules (no `/` prefix, no `..`, no `\`, no `:`). Media are referenced by scene asset key and archive-relative path; the scene names store UUIDs, never paths. Reader and writer live in `Packages/SceneArchive`. |
| Gap: slideshow | A photo asset's MED-006 slideshow (`slideshow.storeIDs`, up to 20 pictures) is carried as scene JSON only: its pictures are **not** packed, so after an import on another device every slide is missing. |
| Archive service (app) | `SceneArchiveService`: export from the stores by store ID to a temporary file; import with a dry run (FILE-003 `planImport`), staging through the stores' own import paths, adoption (FILE-008 dedup) and then **making the photo, video and logo current** (FILE-001 semantics). No screen calls it. |
| Show import (FILE-004) | `ShowStore.planSceneImport` / `installImportedScenes`: all-or-nothing install with Keep both (derived scene ID, "copy" name) / Skip / Replace, a cue appended per added scene. "The scene import screen (SCN-014) is not built: the app does not call this yet." |
| Repair report (SCN-012) | `SceneRepairReport` lists missing media, unknown layers and invalid mappings; the FILE-003 plan carries its entries. |
| Media relinking (MED-013) | `SceneDocument.mediaReferences` lists photo, slide, logo and video references; MED-013 assigned "an app screen that imports scene archives" to this row. |
| Media stores | MED-001/002/010 copy every picked file into the app's own folders (metadata-free copies); scenes never reference the Photos library, the Music library or any file outside the app. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: What is a "dependency pack"? → A: The existing FILE-001 `.pmscene` scene archive, extended so that it also carries the slideshow's pictures. One scene per pack. Every media reference in the pack is an archive-relative path (`assets/…`) tied to a scene asset key; no file name from the device, store UUID-to-path mapping or container path is written.
- Q: Which media are "permitted"? → A: Only media the user imported into the app: the photo (MED-001), its slideshow pictures (MED-006), the logo (MED-010) and the video (MED-002), taken from the app's own folders by store ID. Nothing from the Photos or Music library, no DRM content, no file outside the app's folders. Text and generator graphs stay embedded in the scene.
- Q: How are slideshow pictures packed? → A: As `assets/<key>-slide-<NN>.<ext>` (NN = 01…20, the slide's position), listed in an optional manifest field `slides` written only when the scene has slides, so a pack without slides keeps FILE-001's bytes. An app without SCN-014 refuses a pack with slides (unexpected file), as an app without MED-010 refuses one with a logo; no format version change.
- Q: How is "no absolute path" enforced? → A: The export refuses a pack in which any manifest or scene string looks like a filesystem location (research SCN-014-D2: starts with `/` followed by a system root such as `var`, `private`, `Users`, `Library`, `System`, `Applications`, `tmp`, `Volumes`, or starts with `file:` or `~/`, or contains `Containers/Data/Application`); every entry name already passes `ArchivePath`. Free text a user typed (text layers) is not rejected unless it is such a location.
- Q: Where is Export? → A: Settings → Show → Scene Folders: each scene row's context menu, a VoiceOver action "Export Scene", hands the pack to the system share sheet (Save to Files, AirDrop and others). The temporary file is removed when the sheet closes.
- Q: Where is Import? → A: Settings → Show → Scene Folders: an "Import Scene…" row opens the system file picker for `.pmscene` files.
- Q: What does Import do? → A: It shows a preview first (the dry run): scene name, number of photos, slides, logos and videos, total size, whether the scene ID is already in the show (it would be added as a copy under a new ID) or identical (nothing to add), SCN-012 repair entries and licence records (always "none": the pack holds only the user's own media). On Import: every media file is staged through the store's own import path, adopted into the store (FILE-008: an equal picture or video is stored once), the scene is installed with FILE-004 Keep both (new scene ID and "copy" name when the ID is taken) and one cue is appended. Nothing is applied and the current photo, video, logo and slideshow stay as they are.
- Q: What is deduplicated on re-import? → A: Media: the stored copies get identifiers derived from the pack's media bytes, so importing the same pack again reuses the same identifiers and payloads (no second copy). Scenes: the re-imported scene is then byte-identical to the stored one, so FILE-004 reports it identical and nothing is added.
- Q: Network? → A: None, ever. The pack is self-contained.

### Session 2026-11-14 (speckit-clarify)

- Q: Does the preview offer Replace or Skip when the pack's scene ID is already in the show? → A: No: a pack is always added as a copy (FILE-004 Keep both) or reported identical. Replacing a stored scene from a file is destructive and stays out of this row; the user can delete the old cue afterwards.
- Q: Which folder does an imported scene go into? → A: The top level (SCN-004), as SCN-011 templates do; the user can move it.
- Q: Does Import move the show to the new cue or apply it? → A: No: the cue is appended, the position and output stay (SHOW-001-R6); the result is announced ("Imported <name> as cue <n>.") on the library lane.
- Q: Are archives exported before SCN-014 (FILE-001 packs without slides) accepted? → A: Yes: they are the same format; only the `slides` field is new and optional.
- Q: Must re-imported pictures be byte-identical even though opaque pictures are JPEG? → A: Yes (research SCN-014-D9): the import keeps the pack's bytes when they carry no more metadata than a fresh sanitized copy, so export → import never re-encodes; any other picture is sanitized as before.
- Q: How is long work shown? → A: Export and import run off the main actor; the row shows a progress indicator and is disabled until done. No time limit is promised (videos may be large).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Export a scene with its media (Priority: P1)

A performer prepares a scene with a photo, a two-picture slideshow, a logo and a text caption, and sends it to a second device or keeps it in Files as a backup.

**Why this priority**: It is the roadmap row's first half.

**Independent Test**: Export a scene that names a photo, two slides, a logo and text; the pack contains every picture and no absolute path.

**Acceptance Scenarios**:

1. **Given** a stored scene naming a photo, two slides, a logo and text, **When** the user exports it, **Then** the share sheet receives one `.pmscene` file containing the scene, the photo, both slides and the logo, and no string in it starts with `/` or `file:` or names a container folder.
2. **Given** a scene naming a photo that is no longer stored, **When** the user exports it, **Then** nothing is written and the user reads which media is missing.

### User Story 2 - Import a pack into the show (Priority: P1)

On a fresh install (or the same device after erasing media and show), the performer imports the pack offline and gets the scene back as a new cue.

**Why this priority**: The roadmap row's acceptance.

**Independent Test**: Wipe stores, import the pack offline; the scene equals the original apart from identifiers, every media reference resolves to byte-identical pictures, and a cue appears.

**Acceptance Scenarios**:

1. **Given** empty media and show stores and no network, **When** the user imports the pack and confirms, **Then** the scene is stored, a cue for it is appended, and its photo, slides and logo resolve to pictures byte-identical to the exported ones.
2. **Given** a pack whose scene ID is already in the show with different content, **When** it is imported, **Then** it is added as a copy under a new scene ID and the stored scene is unchanged.
3. **Given** the same pack imported twice, **When** the second import is previewed, **Then** it reports the scene as already in the show and no media file is stored twice.
4. **Given** a pack missing a listed media file, or with an entry named `../x` or `/x`, **When** it is previewed, **Then** it is refused with a reason and nothing is written.

### Edge Cases

- The show is full (256 cues): the preview says so and Import is unavailable.
- A pack from a newer app (unknown asset type, newer scene version): refused by FILE-001 and SCN-001 with their messages.
- The file picked is not a pack: refused ("not a scene archive").
- An import fails after media were adopted (scene write fails): the newly adopted media are released; media that were already stored stay.
- Export while another export's share sheet is open: the earlier temporary file is replaced.

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-014-R1**: A pack carries the scene document and every permitted media file it names (photo, slides, logo, video), each under an archive-relative path; nothing else.
- **SCN-014-R2**: The export refuses, writing nothing, a scene whose named media are not all stored on the device, and a pack in which a manifest or scene string is an absolute filesystem location (Clarifications).
- **SCN-014-R3**: Slideshow pictures are packed in slide order as optional `slides` records; a pack without slides is byte-identical to FILE-001's.
- **SCN-014-R4**: The reader accepts slides only for the scene's photo asset, in positions 1…N matching the scene's slideshow list, with exact paths, PNG or JPEG content and photo limits; anything else is refused.
- **SCN-014-R5**: Import previews before writing (dry run): scene name, media counts by kind, total size, show conflict (new, identical, copy under a new ID, show full), SCN-012 entries and licence records; nothing is written by the preview.
- **SCN-014-R6**: Import stages every media file through its store's import path, adopts it with an identifier derived from its bytes (FILE-008 dedup), installs the scene with FILE-004 Keep both and appends one cue; it never makes media current, never applies a scene and never moves the position.
- **SCN-014-R7**: Import is all or nothing: a refusal or failure leaves the show unchanged and releases only media this import added.
- **SCN-014-R8**: Import and export use no network API; the picked file is read once under its security scope.
- **SCN-014-R9**: Export and Import are reachable in Scene Folders by touch, context menu and VoiceOver actions; results and refusals are announced on the library lane (ACC-004); while one runs, its control shows progress and is disabled.
- **SCN-014-R10**: An imported scene is never written over a stored scene: a taken scene ID gives a copy under a new ID (no Replace), and the scene goes to the top level.

### Key Entities

- **Scene pack**: the `.pmscene` file: manifest, scene, media files.
- **Slide record**: asset key, position, archive path.
- **Pack preview**: what an import would do (R5).

## Success Criteria *(mandatory)*

- **SCN-014-S1**: An exported pack of a scene with a photo, two slides, a logo and text contains 0 absolute paths (acceptance test scan of every manifest and scene string and entry name).
- **SCN-014-S2**: After wiping media and show stores, importing the pack offline gives a scene equal to the original apart from identifiers, with 4 of 4 media references resolving to byte-identical pictures.
- **SCN-014-S3**: Importing the same pack twice stores each picture once and adds no second scene or cue.
- **SCN-014-S4**: 100% of crafted packs with traversal or absolute entry names, or a missing media file, are refused with nothing written.
- **SCN-014-S5**: A user exports a scene and imports a pack from Scene Folders and sees the new cue in under 30 s of UI-test time.

## Assumptions

- One scene per pack; whole shows travel through FILE-005 backups.
- The pack does not carry cue labels, transitions, folders or tags (show data, not scene data); the imported scene goes to the top level.
- Packs may be large (videos up to the store limit, 600 MB archive limit from FILE-001).
- No device evidence is needed: file and UI logic, tested on the host and simulator.
