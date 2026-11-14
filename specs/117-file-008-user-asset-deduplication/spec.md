# Feature Specification: FILE-008 User Asset Deduplication

**Feature Branch**: `feature/file-008` (spec directory `117-file-008-user-asset-deduplication`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement FILE-008 (User asset deduplication) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Store identical imported media once
by content hash." Acceptance, verbatim: "Two identical imports create one physical payload and two
references." P1, L, depends on MED-001 (integrated). Verification: schema and fixture tests plus the
simulator."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `FILE-008-R1…`, success criteria `FILE-008-S1…`, tasks `FILE-008-T01…`.

## Baseline: where imported media live today (audit of 2026-11-14, commit `0042267d`)

The row's gap status is "Gap candidate". The audit confirms a gap: every photo or video import writes a
new copy under a new identifier, even when the bytes are identical to what is already stored.

| Media | Where it lives | How it is referred to | Deduplicated today? |
|---|---|---|---|
| The photo (MED-001) | `Application Support/Photos/<UUID>.png|jpg`, one sanitized copy; **single slot**: making a photo current deletes the previous copy | UserDefaults `settings.photo.id`; scenes, show cues (SHOW-001 `ShowSceneSnapshot`), the SCN-002 autosave and scene history hold `SceneAsset.photo(storeID: <UUID>)` | **No**: re-importing the same picture writes a second copy under a new UUID and deletes the first, so scenes and cues that named the first UUID report "no longer stored" |
| The video (MED-002) and its loop region (MED-003) | `Application Support/Videos/<UUID>.mov`, one remuxed copy; single slot | `settings.video.id`; `settings.video.loop` keyed by the video UUID; scenes and cues hold `SceneAsset.video(storeID:)` | **No**; worse, the remux writes the import time into the movie header, so two imports of one file never produce equal bytes |
| Text (MED-009) | UserDefaults `settings.text.overlay` | Embedded in scenes | Not media; out of scope |
| Imported audio (AUD-001) | `Application Support/AudioLibrary/assets/<sha256>.<ext>` + `index.json` | Track records by ID | **Yes** already (content-addressed; an identical import reuses the record). Out of scope; its pattern is reused |
| Scene archives (FILE-001/002/003) | Import stages the archive's photo and video in `tmp`, adopts them into the stores, then makes them current (`replacedPhoto`, `replacedVideo`) | Remapped store IDs in the imported scene | No: adopting a picture already stored adds a second copy |
| Library backup (FILE-005, ADR-0041) | Reads `Photos/<UUID>.png|jpg` files; restore writes those names into a staged copy of `Photos/` | `photos/<UUID>.ext` entries with their SHA-256 in the manifest | Must stay exact |
| Storage screen and cache cleanup (FILE-009, FILE-010) | Measure the `Photos` and `Videos` folders; never clean them | — | Counts physical files |
| Memory pressure (PERF-006) | Releases decoded pictures and players, never stored files | — | Unaffected |

**Reference model** (decided here): the stores stay single-slot (one current photo, one current video;
the user model of MED-001/002 is unchanged). A **reference** is a store identifier (a UUID) that the
store resolves to a stored payload. Scenes, cues, the autosave and history keep naming identifiers, as
today. Two identical imports give two identifiers (two references) that resolve to one payload, so a
scene or cue saved after the first import still finds its picture after the second.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Are photos and videos a library or a single slot? → A: A single slot each (audit above). FILE-008 does not turn them into a library: "two references" are two store identifiers for the same content (the current one and earlier ones that scenes, cues or the autosave may name).
- Q: What does a store keep when the current photo or video changes? → A: Only the current content. References whose payload equals the new current payload stay (they are the same picture); every other reference is released and a payload with no reference left is deleted at once. Remove Photo / Remove Video releases every reference and deletes the payload (MED-001-R7 and MED-002-R7 unchanged: the bytes leave the device).
- Q: When are two payloads "identical"? → A: Equal SHA-256 of the stored (sanitized) bytes and equal byte size. A SHA-256 collision is not considered further (probability negligible; recorded in the ADR).
- Q: Why must the video copy change? → A: The remux writes the current time into the movie's three header times, so equal sources never give equal copies. The sanitized copy now carries zero header times; this also removes the import time from the stored file (privacy gain, no playback change).
- Q: How do existing stored copies move to the new layout? → A: Once, at launch, after the FILE-005 restore recovery and before any import: each old `<UUID>.ext` file is moved into the content-addressed layout under the same identifier. Every step is atomic and repeatable, so an interruption at any point is finished at the next launch; old identifiers keep resolving before, during and after.
- Q: Does the backup change? → A: No. A backup still lists `photos/<UUID>.ext` with that reference's bytes; two references to one payload appear as two entries with equal bytes. A restore writes plain files that the next launch's migration deduplicates.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Re-importing the same media keeps one copy (Priority: P1)

A user imports a photo, saves show cues using it, later picks the same photo again (or imports a scene
archive that carries it). The device keeps one copy; the earlier cues still show the picture.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: Import one photo twice into a temp store: the store folder holds one payload file
and the store reports two references; both identifiers resolve to that file. The same with the small
fixture video.

**Acceptance Scenarios**:

1. **Given** a stored photo with identifier A, **When** the same picture is imported again (identifier B), **Then** one payload file exists, A and B both resolve to it, and B is current.
2. **Given** a cue that names A, **When** B becomes current, **Then** the cue's photo is reported present (no "no longer stored" notice).
3. **Given** the fixture video imported twice, **When** both imports finish, **Then** one payload file exists and two references resolve to it.
4. **Given** a scene archive whose photo equals the stored one, **When** it is imported, **Then** no second payload is written.

### User Story 2 - Releasing references deletes bytes only when unused (Priority: P1)

**Independent Test**: With two references to one payload, release one: the payload stays and the other
resolves; release the second: the payload is gone. A different photo made current releases all
references to the old content and deletes it.

**Acceptance Scenarios**:

1. **Given** references A and B to one payload, **When** A is released, **Then** the payload remains and B resolves.
2. **Given** only B, **When** B is released, **Then** no payload remains.
3. **Given** references to photo X, **When** a different photo Y becomes current, **Then** X's payload and references are gone.
4. **Given** stored media, **When** Remove Photo / Remove Video runs, **Then** the store folder holds no payload.

### User Story 3 - Existing copies migrate safely (Priority: P1)

An update installs over a device that stores `<UUID>.png` and `<UUID>.mov`. At the next launch they move
into the new layout; nothing the user saved breaks, even when the app is killed mid-way.

**Independent Test**: A fault injected at every step of the migration, then a rerun: every old
identifier resolves to the original bytes and the layout is complete with no stray files.

### User Story 4 - Backups, archives and the storage screen stay right (Priority: P2)

**Independent Test**: A FILE-005 backup of a deduplicated library equals, entry for entry, the backup of
the same library before deduplication, and restores exactly; the storage screen counts the payload once
and says how much the shared copies save.

### Edge Cases

- A payload file is damaged or deleted on disk: its references read as "no photo/video" (MED-001-R14, MED-002-R18), as a missing file does today.
- An old plain file and a reference for the same identifier both exist (a restore wrote a newer copy): the plain file wins and replaces the reference.
- Garbage left by an interruption (a half-written payload, an unreferenced payload, a temporary file): removed at the next launch.
- The registry file is damaged: references are rebuilt from nothing; payloads with no reference are deleted, so the store reads as empty (the same result as a missing file today) — never another file.
- Two imports of the same content at once: serialized per folder; one payload results.

## Requirements *(mandatory)*

### Functional Requirements

- **FILE-008-R1**: Photo and video stores keep each distinct content once, as a payload named by its SHA-256 and extension, plus a registry mapping each store identifier (reference) to its payload.
- **FILE-008-R2**: An import computes the hash by streaming the stored copy (never the whole file in memory); when an equal payload (hash and byte size) exists, the import adds a reference and writes no second payload.
- **FILE-008-R3**: Store identifiers keep their format (canonical UUID) and meaning: settings, scenes, cues, autosave, history and archives are unchanged; resolving accepts only a canonical UUID and payload names inside the store folder (MED-001-R14, MED-002-R18 kept).
- **FILE-008-R4**: Making a content current keeps references to the same payload and releases all others; releasing the last reference of a payload deletes it immediately; Remove deletes every reference and payload.
- **FILE-008-R5**: Every identifier that resolves (not only the current one) counts as present when scenes and cues are checked for missing media.
- **FILE-008-R6**: The video copy's movie-header creation and modification times are zero, so equal sources give equal copies.
- **FILE-008-R7**: A launch-time migration moves old `<UUID>.ext` copies into the layout; each step is atomic and repeatable; an interrupted migration completes at the next launch; old identifiers resolve at every point.
- **FILE-008-R8**: The same launch pass removes temporary files and payloads without a reference; mutations of one folder are serialized.
- **FILE-008-R9**: FILE-005 backups list every reference as `photos/<UUID>.ext` with its bytes, so a backup and its restore are exact; restored plain files are deduplicated by the next migration.
- **FILE-008-R10**: Scene-archive import (FILE-001) of media already stored adds a reference, not a payload, and does not report the photo or video as replaced.
- **FILE-008-R11**: The storage screen keeps counting physical files and shows the space shared copies save when there is any.
- **FILE-008-R12**: Local only: no networking, public APIs only, no new privacy-manifest reason.

### Key Entities

- **Payload**: one stored file `<sha256>.<ext>`; its byte size.
- **Reference**: a store identifier (UUID) mapped to a payload name in the folder's registry.
- **Registry**: `references.json` in the store folder: format version and the reference map.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FILE-008-S1**: Two identical photo imports leave exactly 1 payload file and 2 references; the same for the fixture video.
- **FILE-008-S2**: Releasing 1 of 2 references leaves the payload; releasing both leaves 0 payload files.
- **FILE-008-S3**: A fault at each of the migration's steps, followed by a rerun, leaves every old identifier resolving to its original bytes in 100% of the injected cases.
- **FILE-008-S4**: A backup of a deduplicated library and its restore into an empty library are exact (every record equal).
- **FILE-008-S5**: Importing a scene archive whose photo is already stored adds 0 payload files.
- **FILE-008-S6**: The storage screen's Photos figure counts the shared payload once and its note shows the saved size.

## Assumptions

- Single-slot stores stay; a photo/video library is not part of this row.
- The ImageIO photo sanitizer gives equal bytes for equal input (verified by the acceptance test).
- Audio library deduplication already exists (AUD-001) and is unchanged.
- Device evidence is not required: the behaviour is file-system logic verified on the Mac host and simulator.
