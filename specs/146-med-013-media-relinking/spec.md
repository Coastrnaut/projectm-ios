# Feature Specification: MED-013 Media Asset Relinking

**Feature Branch**: `feature/med-013` (spec directory `146-med-013-media-relinking`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MED-013 (Media asset relinking) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Locate missing imported media by
checksum and user-selected replacement." Acceptance, verbatim: "Missing asset shows placeholder;
relink restores all scene references." P1, size M, depends on MED-002 (integrated)."

Identifiers carry the roadmap ID: requirements `MED-013-R1…`, success criteria `MED-013-S1…`, tasks
`MED-013-T01…`, research decisions `MED-013-D1…`. Other features are cited by their own IDs: MED-001
(photo), MED-002 (video), MED-006 (slideshow), MED-010 (logo), AUD-001 (imported audio), SCN-001 (scene
document), SCN-012 (repair report), SCN-013 (scene migration), SHOW-001 (cue list), FILE-005 (library
backup), FILE-006 (folder backup and media restore), FILE-008 (content-addressed media store,
ADR-0043), FILE-009 (Storage screen), FILE-011 (erase), ACC-004 (announcer).

## Baseline: what exists today (audit of 2026-11-14, commit `4bad23aa`)

| Area | Today |
|---|---|
| Media store | FILE-008 / ADR-0043: `Photos` and `Videos` folders hold payloads `<sha256>.<ext>` plus `references.json` (store identifier, a canonical UUID → payload name). `resolve(id)` returns nil when the entry is gone or its payload file is missing. |
| Identifiers | Scenes, cues, settings, archives and backups name media by store identifier (UUID), never by hash (ADR-0043, MED-001-R14, MED-002-R18). |
| Who references photos | Scene `photo` assets (MED-001), each photo asset's optional `slideshow.storeIDs` (MED-006), scene `logo` assets (MED-010); settings `settings.photo.id`, `settings.photo.slideshow`, `settings.logo.id`. |
| Who references videos | Scene `video` assets (MED-002); setting `settings.video.id` (plus loop and speed keyed by it). |
| Saved scenes | SHOW-001: `Show/Scenes/<SCENE-ID>.scene.json`, one per scene a cue refers to. `ShowStore.referencedMediaIDs()` lists photo and video IDs (not slides or logos). |
| Missing media today | SCN-001 validation flags `missingAsset` (photo, video, logo); SCN-012's repair report lists it ("Its layer draws nothing until the media is stored again") and "Open with repairs" drops it. A show cue that applies such a scene adds the notice "the scene's photo or video is no longer stored; the current one is shown." Nothing shows a placeholder, nothing lists missing media across scenes, and nothing restores it. |
| How media goes missing | Making a new photo or video current releases the previous content (ADR-0043 Decision 3: slides and the logo are protected, scenes are not), Remove releases it, a FILE-011 erase removes it, and files can be lost outside the app (restore of a partial device backup). |
| Settings references | `PhotoStore.current()`, `LogoStore.current()` and `SlideshowStore.settings()` drop identifiers that no longer resolve when read (MED-001-R14, MED-006-R10). |
| Backups | FILE-005 lists photos by logical names `<UUID>.<ext>`; a FILE-006 folder backup holds exact copies `photos/<UUID>.<ext>` (the stored payload bytes) and a media restore writes legacy files only for identifiers that do not resolve. |
| Imported audio | AUD-001 has its own content-addressed library; no scene or cue references imported audio, so it has nothing to relink. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: What counts as "missing media"? → A: A photo or video store identifier named by a saved scene (photo asset, slideshow slide, logo, video asset) that does not resolve in its store. Settings values are not listed: they already clean themselves when read (MED-001-R14, MED-006-R10), and a relink also rewrites them when they still name the old identifier.
- Q: How does a missing asset look? → A: When a cue applies a scene whose media is missing, the visualizer shows an accessible "Missing media" placeholder tile naming the scene, with a Relink button that opens the Missing Media screen. The scene's reference is never dropped and nothing crashes; the SCN-012 repair report keeps listing it. The tile goes away when the media resolves again or another scene without missing media is applied.
- Q: Is relinking by checksum free with content addressing? → A: Partly. When the payload file is gone but the registry entry remains, importing the same bytes again recreates `<sha256>.<ext>` and the old identifier resolves with no scene edit. When the registry entry itself was released (a new photo made current, Remove, a scenes-only erase), its hash was lost. So the registry keeps, for released identifiers, a bounded list of `{id, payload}` (at most 256, oldest dropped) inside `references.json` as an optional key; an identifier whose payload is present again is re-registered (adopted) and resolves.
- Q: When is the checksum match applied? → A: Automatically after every photo or video import and whenever the Missing Media screen opens or refreshes; also by "Find Missing Media in Folder…".
- Q: What does "Find Missing Media in Folder…" read? → A: A folder the user picks (security-scoped, read-only). Files are matched by SHA-256 of their exact bytes against the payload names of missing identifiers, so a FILE-006 folder backup or an exported copy matches; a matching file is copied into the store. Bounds: at most 5,000 directory entries visited, depth 4, at most 1,000 files hashed, files up to the store's import size limit, 4 GiB hashed in total; hidden files, symbolic links and packages are skipped; the scan stops early once every missing hash is found.
- Q: How does relink by replacement work? → A: The user picks a different file for one missing identifier. It is imported through the store's normal import (sanitized photo copy, sanitized video copy) under a new identifier, then every reference to the old identifier in every saved scene (photo asset, slides, logo, video asset) and in the settings values is rewritten to the new identifier, all or nothing. The report says how many scenes, cues and references changed and that the picture or video differs from the original.
- Q: Where is it in the app? → A: Settings → Storage → Missing Media: one row per missing asset (kind, short identifier, number of scenes and cues using it, whether its checksum is known), with Relink… (replacement) per row, and Find Missing Media in Folder… for all. Results are announced on the announcer's library lane.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Does the released-hash list keep payload bytes alive? → A: No. It is a list of names only; payloads still go with their last reference (ADR-0043 Decision 3 unchanged). It is not a reference, it is not counted in Storage, and backups do not carry it.
- Q: What happens to the released-hash list on FILE-011 erase? → A: Erasing photos and videos removes the folders, so the list goes with them; a scenes-only erase forgets the identifiers it releases. After an erase, scenes from another source (an archive import) that name erased media can still be relinked by replacement.
- Q: Is a scene rewrite all or nothing even across several files? → A: Yes. Every new scene file is written to a temporary name first; then each original is kept as a hard link and the new file renamed over it; any failure renames the kept originals back and removes the temporary files, so either every scene names the new identifier or none does. The settings change only after the files succeeded; a staged replacement copy is discarded on failure. SCN-013's original-version backup is kept before an older-format file is replaced.
- Q: Can an identifier relinked by checksum be released again? → A: Yes, under FILE-008's rules (it is an ordinary reference). Changing which photos the single-slot store protects is outside this row; the Missing Media screen will list it again and the released-hash list allows another checksum relink.
- Q: Are scenes with unreadable files rewritten? → A: No; they cannot be decoded. The report counts them, and they stay listed as "Scene missing" (SHOW-001). Readable scenes are still rewritten.

### Session 2026-11-14 (speckit-analyze)

- Finding (coverage, acceptance wording): a saved scene exists only while a cue refers to it (SHOW-001), so "scenes A and B and a show cue" means two cues, one per scene, and the cue in the acceptance is A's cue. The missing list therefore shows P "used by 2 scenes, 2 cues"; the cue count is the number of cues whose scene uses the identifier (a scene shown by two cues counts twice). Applied to the acceptance test (MED-013-T12).
- Finding (consistency): MED-013-R4's "after every import" covers the photo and video stores' imports; slideshow and logo pictures are staged into the same Photos folder, and the Missing Media screen's refresh adopts their matches too. No new task needed.
- Finding (underspecified): which item a Relink… replacement accepts: a photo item opens the image picker (PNG, JPEG, HEIC through the photo import), a video item the movie picker (the video import's types). Applied to MED-013-T11.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I see that media is missing and get it back by checksum (Priority: P1) — MVP

Scenes A and B and a show cue use photo P; scene B's slideshow includes P. P's file is lost. Stepping
to the cue shows a "Missing media" tile instead of failing; Settings → Storage → Missing Media lists P
"used by 2 scenes". The user imports the same picture again (or finds it in a backup folder): every
scene resolves P again, with no scene edits.

**Independent Test**: Seed the scenes and cue, delete P's payload, check the placeholder state and the
missing list, intern the same bytes, check every reference resolves and the list is empty.

**Acceptance Scenarios**:

1. **Given** P's payload deleted, **When** the cue applies scene A, **Then** the placeholder shows and the scene still names P.
2. **Given** P missing, **When** the Missing Media list is built, **Then** it shows P with 2 scenes (and the cue count).
3. **Given** P missing, **When** the same bytes are imported again, **Then** every reference to P resolves and the list is empty.
4. **Given** P's registry entry released, **When** the same bytes are imported, **Then** P is adopted from the released-hash list and resolves.
5. **Given** a folder holding P's bytes and unrelated files, **When** the user runs Find Missing Media in Folder…, **Then** P is restored, the other files are ignored and nothing in the folder changes.

---

### User Story 2 - I replace missing media with another file (Priority: P1)

The original is gone for good; the user picks another picture for P. Every reference to P in A, B, the
cue's scene and B's slideshow now names the new identifier, and stays so after a relaunch.

**Independent Test**: Replace P, check every reference in every scene file names the new identifier,
reload the scenes from disk, and fault the rewrite at each step to check nothing changed.

**Acceptance Scenarios**:

1. **Given** P missing, **When** the user relinks it to another file, **Then** A, B, the cue's scene and B's slides name the new identifier and the report states 2 scenes and that the content differs.
2. **Given** that relink, **When** the scenes are reloaded from disk, **Then** the new identifier persists.
3. **Given** a failure during the rewrite, **When** it happens at any step, **Then** every scene file is byte for byte as before, the staged copy is discarded and the settings are unchanged.

---

### User Story 3 - Limits and erase stay safe (Priority: P2)

**Independent Test**: Scan bounds stop the walk and say so; an erase leaves no released-hash list; an
unreadable scene is counted and skipped.

**Acceptance Scenarios**:

1. **Given** a folder with more entries than the bound, **When** it is scanned, **Then** the scan stops at the bound and the result says the folder was not fully searched.
2. **Given** a photos-and-videos erase, **When** it completes, **Then** no released-hash list remains and scenes naming erased media are listed with "checksum unknown".
3. **Given** a scenes-only erase, **When** it completes, **Then** the released identifiers are not in the released-hash list.

### Edge Cases

- A missing identifier with no known checksum (a legacy file lost before migration, or erased) can only be relinked by replacement; its row says "Checksum unknown".
- The same missing identifier used by several scenes and cues is one row with the counts.
- Replacing with a file the store refuses (wrong type, too large) changes nothing and says why.
- Replacing with a picture whose copy equals another stored picture shares its payload (FILE-008).
- A folder scan that finds nothing says "No matching files were found."; cancelling the picker changes nothing.
- Relinking a video by replacement keeps each scene's own loop and speed fields (they are part of the scene's video asset); the loop and speed the settings keep per identifier are not carried over, because the content differs.
- The placeholder never covers the safety controls (blackout, settings); it is a small tile.

## Requirements *(mandatory)*

### Functional Requirements

- **MED-013-R1**: The app lists missing media: every photo or video store identifier named by a readable saved scene (photo asset, slideshow slide, logo, video asset) that does not resolve, with its kind, the number of scenes and cues using it, and whether its checksum is known.
- **MED-013-R2**: A cue that applies a scene with missing media shows an accessible "Missing media" placeholder tile (label "Missing media", value naming the scene) with a Relink button; the scene's references are never removed by applying it; the tile clears when the media resolves or a scene without missing media is applied.
- **MED-013-R3**: The media registry keeps the payload names of released identifiers (at most 256, oldest dropped) as an optional key of `references.json` (format version unchanged); it holds names only and never keeps a payload alive.
- **MED-013-R4**: Relink by checksum: a missing identifier whose registry entry or released entry names a payload that exists again resolves (re-registered when needed) with no scene edit; this runs after every photo or video import and whenever the Missing Media screen opens or refreshes.
- **MED-013-R5**: Find Missing Media in Folder… scans a user-picked folder read-only under its security scope, with the bounds of the Clarifications, matches exact bytes by SHA-256 against missing payload names, copies matches into the store (verified again), ignores everything else, and reports found, scanned and whether a bound stopped it.
- **MED-013-R6**: Relink by replacement imports a picked file through the store's normal import under a new identifier and rewrites every reference to the old identifier in every readable saved scene and in the settings values (`settings.photo.id`, slideshow slides, `settings.logo.id`, `settings.video.id`), all or nothing; on failure the staged copy is discarded and nothing else changes.
- **MED-013-R7**: The rewrite keeps SCN-013's original-version backup rule and writes canonical SCN-001 bytes; scene IDs, names, cues and every other field are unchanged.
- **MED-013-R8**: Every relink reports what changed (identifiers relinked, scenes, cues and references rewritten, scenes skipped as unreadable) and a replacement states that the content differs from the original; results and refusals are announced on the announcer's library lane.
- **MED-013-R9**: FILE-011: erasing photos and videos removes the released-hash list with the folders; a scenes-only erase forgets the identifiers it releases.
- **MED-013-R10**: No networking, no new settings keys, no change to identifiers' format; backups and archives are unchanged.
- **MED-013-R11**: The Missing Media screen is reached from Settings → Storage; each row has Relink… and a VoiceOver action; Find Missing Media in Folder… is one button for all rows; an empty list says "No missing media."

### Key Entities

- **Missing media item**: store (photos or videos), identifier, scenes and cues using it, checksum known.
- **Released entry**: identifier → payload name, kept by the registry for released identifiers.
- **Relink report**: identifiers relinked, scenes/cues/references rewritten, unreadable scenes skipped, content differs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MED-013-S1**: In the acceptance test, the deleted photo is listed with 2 scenes, the placeholder state is set, and after a checksum relink 100% of references (A, B, the cue's scene, the slideshow) resolve.
- **MED-013-S2**: After a relink by replacement, 100% of references to the old identifier in scenes A and B, the cue's scene and the slideshow name the new identifier, also after reloading from disk.
- **MED-013-S3**: A fault at every rewrite step leaves every scene file byte for byte unchanged.
- **MED-013-S4**: The folder scan finds a matching file, ignores non-matching ones and stops at each bound in the tests.
- **MED-013-S5**: On the simulator, a user opens Missing Media, sees the seeded photo used by 2 scenes and restores it from a folder, in a UI test under 30 seconds.

## Assumptions

- Saved scenes are SHOW-001's show scenes (the only named local scenes); the scene autosave and history hold the live look, which names the current media and cleans itself when read.
- The same bytes means the same SHA-256 and size (ADR-0043 Decision 2).
- The system folder and file pickers cannot be automated; the UI test points the folder scan at a DEBUG fixture folder.
- Simulator and Mac results are not device evidence; this row needs no device-only check.
