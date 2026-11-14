# Feature Specification: FILE-005 Local Library Backup

**Feature Branch**: `feature/file-005` (spec directory `114-file-005-local-library-backup`)

**Created**: 2026-11-14

**Status**: Draft

**speckit-analyze (2026-11-14)**: 0 critical, 0 high; every requirement and success criterion maps to a task (R1 T03/T05/T06, R2 T05/T12, R3 T02/T12, R4 T14/T15, R5 T07/T14, R6 T13/T14, R7 T08/T11, R8 T09, R9 T04/T09, R10 T07/T10, R11 T09, R12 T14/T16, R13 T17/T18; S1 T09, S2 T11, S3 T10, S4 T12, S5 T06, S6 T16). Fixes applied: the older-version path of R3 gets a test in T12; the launch-time result reports the counts actually installed, which can differ from the preview when the library changed in between (R6).

**Input**: User description: "Implement FILE-005 (Local library backup) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Export scenes, collections and
mappings into one user-selected file." Acceptance, verbatim: "Restore on fresh sandbox recreates exact
local logical records." P1, L, depends on FILE-001 (integrated). Verification: schema and fixture tests
plus the simulator."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `FILE-005-R1…`, success criteria `FILE-005-S1…`, tasks `FILE-005-T01…`.

## Baseline: the user's local logical records (audit of 2026-11-14, commit `e74970a7`)

The row's gap status is "Gap candidate". The audit confirms a gap: each kind of record can be exported
on its own (one scene, FILE-001; checked presets, PRE-014) but nothing saves the library as a whole,
and nothing restores the show, the collections, favorites or settings.

| Record | Where it lives | In the backup? | Why |
|---|---|---|---|
| The show: cue list and its scenes (SHOW-001, SCN-003) | `Application Support/Show/show.json`, `Show/Scenes/<ID>.scene.json` | **Yes** | The roadmap's "scenes"; scenes carry the MOD-002 bindings and layer settings (the "mappings" inside a scene) |
| The current scene (SCN-002 autosave) | `Application Support/Scenes/current.scene` | **Yes** | The scene the user is working on; one document |
| Scene backups (`*.v<N>.backup`, `current.scene.bak`, damaged show files set aside) | Same folders | No | Recovery copies, not records; they are rebuilt by the stores as needed |
| My Presets: imported presets and copies of Included presets (PRE-012, PRE-015) | `Application Support/UserPresets/index.json`, `files/<sha256>.milk` | **Yes**, the record and its text | The user's own presets |
| Copies of presets from the full library (purchased packs) | Same | **No** | The purchase stays on its account and device (ADR-0008, PRE-014-R2): a backup must never copy paid content |
| Quarantined presets | `UserPresets/quarantine/` | No | They failed a check and can never play; carrying a hostile text between devices helps nobody |
| The check state of a preset (checked, proven on screen) | `index.json` | No (re-established) | A file cannot vouch for a text: a restored preset waits for its check (PRE-012 trial) like any import |
| Collections (PRE-007) | `Application Support/PresetCollections/collections.json` | **Yes** | The roadmap's "collections"; names, order, preset identifiers |
| Favorites and the last preset (T089) | UserDefaults `favorites`, `lastPresetID` | **Yes** | Identifiers only; a favorite of a purchased preset is a name, not content |
| Settings: visual, options, glow, spectrum, camera, audio trim, channel, gate, latency offsets, OSC port, Reduce flashing, performance overlay, preset scope, text overlay (MED-009) | UserDefaults `settings.*` | **Yes**, the listed keys | The roadmap's "mappings" outside scenes (OSC port) plus the settings that shape the scenes |
| OSC on, MIDI on | UserDefaults `settings.osc.enabled`, `settings.midi.enabled` | No | Device switches that open a local network listener or MIDI access: the user turns them on again on the device, where iOS asks |
| The photo (MED-001) and its identifier | `Application Support/Photos/<UUID>.png|jpg`, `settings.photo.id` | **Yes** | Scenes refer to photos by store ID; photos are pixels-only copies, bounded in size |
| The video (MED-002), its identifier and loop region (MED-003) | `Application Support/Videos`, `settings.video.id`, `settings.video.loop` | No | Up to 500 MB each; the original is still in the user's Photos or Files; the loop region means nothing without its video. A scene that used it shows the existing "no longer stored" notice (SCN-003-R9). FILE-006 (incremental media) is the place for large media |
| Imported audio (AUD-001) | `Application Support/AudioLibrary` | No | Large, and the user's own files elsewhere; not part of scenes, collections or mappings |
| Recordings, shares, exports, caches | `tmp`, `Library/Caches` | No | Temporary or regenerated |
| Notices, permission explanations, session recovery, guide state | UserDefaults `notice.*`, `permission.*`, `session.*`, `guide.*` | No | Device state; the photosensitivity notice must be acknowledged on each device |
| The StoreKit entitlement | StoreKit (no stored flag) | **No, never** | The purchase is restored by the App Store on the same account, never by a file |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What goes into the backup? → A: The records marked "Yes" in the Baseline: the show and its scenes, the current scene, My Presets (records and texts, except full-library copies and quarantined presets), collections, favorites, the last preset, the listed settings and the photo files. Everything else is left out for the reason given there.
- Q: Are videos and imported audio included? → A: No. They can be hundreds of megabytes, the originals stay with the user, and they are not scenes, collections or mappings. The backup's summary says how many were left out; FILE-006 may add media later.
- Q: How is the file made and where does it go? → A: One file named "projectM Library <date>.pmbackup", saved where the user chooses in Files (the system exporter). It is a ZIP archive with a manifest listing every entry with its SHA-256 and size (FILE-002), the format name and version, the app version, the creation time and the record counts. The temporary copy is deleted when the exporter closes, saved or not.
- Q: When does a restore take effect? → A: At the next launch, before anything loads. The app's screens keep the library in memory and would write their copy back over a restore made while they run, so Restore records the request (a copy of the backup and the chosen options) and asks the user to close and reopen the app; at the next launch the library is planned again with the same choices and installed all or nothing before any store reads it. A pending restore can be cancelled until then.
- Q: How are clashes with the existing library handled? → A: With FILE-004's choices: Skip, Keep both (the default) and Replace, applied to all through one "Apply to all" choice in the preview. Keyed records (scenes, presets, collections, photos) are compared by identifier; single-valued records (the current scene, each setting, the last preset) cannot be kept twice, so Keep both keeps the device's value for them, like Skip, and the preview says so; favorites under Keep both are the union.
- Q: What is a "fresh sandbox" and what is "exact"? → A: A library with none of the backed-up records. Restoring into it recreates every included record exactly: the same identifiers, names, order and content as the backup, compared through each record's canonical encoding (scene bytes, preset text and fields, collection order, setting values), never file dates or names chosen by the store.

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Where do the backup's scenes go when the device already has a show? → A: When the device's show has no cues and no stored scenes, the backup's show and scenes are written exactly (cue IDs, labels, order, position). Otherwise each backup scene goes through FILE-004's scene installer: a new scene or a Keep both copy gets one cue appended (deterministic cue ID), Replace keeps the device's cues, Skip and identical scenes change nothing; the backup's own cue list is not merged (FILE-005-R10).
- Q: How are presets and collections merged into a library that already has some? → A: An empty store (no presets; no collections) receives the backup's records exactly. Otherwise per identifier: new → added (a name already used gets FILE-004's copy name); identical → nothing; clash (same identifier, other content) → the chosen Skip / Keep both (derived identifier "FILE-005|<kind>|<id>|<content SHA-256>|<n>", copy name) / Replace (same identifier, backup's content and name, collection keeps its place). A restore that would exceed 1,000 presets or 100 collections is refused before anything is written (FILE-005-R10).
- Q: What happens to a photo file that clashes, and to the stored photo choice? → A: Photo files are keyed by their store name (`<UUID>.png|jpg`), which scenes refer to, so Keep both cannot rename them: a clashing photo under Keep both or Skip keeps the device's bytes, Replace takes the backup's. The current-photo identifier is a setting like the others; a missing file reads as "no photo" (MED-001-R14) (FILE-005-R10).
- Q: How does the user learn that a restore is pending and how it ended? → A: While a request is pending, Settings › Storage › Backup says "Restore ready. Close projectM-iOS and open it again to finish." with a Cancel Restore button (removes the request; nothing else changes). After the launch-time restore, the same section shows the result once ("Restored from backup: N scenes, M presets, K collections, S settings." or "The restore did not finish. Nothing was changed.") and it is announced on the `library` lane when the screen opens (FILE-005-R6, R12).
- Q: What size limits apply to a backup? → A: The file is at most 512 MiB; at most 4,096 entries besides the manifest; each entry at most 64 MiB; the manifest at most 1 MiB; at most 64 photos. Anything larger is refused before it is interpreted, naming the limit (FILE-005-R2).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Back up the library to a file (Priority: P1)

A user opens Settings › Storage, taps "Back Up Library…", reads what will be saved (counts) and what
is left out, and saves one file in Files.

**Why this priority**: It is the row's observable behaviour.

**Independent Test**: A temp library with every record kind is backed up; the file's manifest lists
the counts and every entry's checksum, and contains no full-library copy, no quarantined text, no video,
no audio and no entitlement.

**Acceptance Scenarios**:

1. **Given** a library with scenes, presets, collections, favorites and settings, **When** Back Up Library runs, **Then** one file is offered to the exporter and the summary says "Backed up N scenes, M presets, K collections and S settings."
2. **Given** copies of full-library presets and a video, **When** the backup runs, **Then** the summary says they were left out and why, and the file holds none of them.
3. **Given** the exporter is cancelled, **When** it closes, **Then** no copy of the backup is left in the app's folders.

### User Story 2 - Restore on a fresh device (Priority: P1)

A user on a new install picks the backup, sees the preview (everything new), taps Restore, reopens the
app and finds the show, scenes, presets, collections, favorites and settings exactly as backed up.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: Populate a temp sandbox with every record kind, back up, restore into a second
empty sandbox, and compare the logical records of both: equal for every record.

**Acceptance Scenarios**:

1. **Given** an empty library and a backup, **When** the restore completes, **Then** every included record of the backed-up library equals the restored one.
2. **Given** a restored preset, **When** the library loads, **Then** it waits for its check before it can play.

### User Story 3 - Restore over an existing library (Priority: P2)

The library already holds some of the backup's records. The preview lists new, identical and clashing
records; the user picks "Apply to all": Keep both, Replace or Skip.

**Independent Test**: Fixture libraries with clashing scenes, presets, collections and settings,
restored with each choice; Skip leaves every clashing record unchanged, Replace takes the backup's
content under the same identifier, Keep both adds copies under deterministic identifiers.

**Acceptance Scenarios**:

1. **Given** a clashing scene and Keep both, **When** the restore completes, **Then** the stored scene is unchanged and the backup's is added under a derived ID with a cue.
2. **Given** a clashing setting and Replace, **When** the restore completes, **Then** the setting has the backup's value.
3. **Given** a clashing preset and Skip, **When** the restore completes, **Then** the preset is byte-identical.

### User Story 4 - Nothing half-restored (Priority: P1)

The restore fails part-way (a full disk, the app is killed). The library is exactly as before, or
exactly the restored one; never a mix.

**Independent Test**: A fault at every file operation of a restore leaves the library snapshot equal to
the one before; an interrupted restore is completed or rolled back at the next launch.

### User Story 5 - Damaged or foreign files are refused (Priority: P1)

A truncated, corrupted, tampered, oversize or newer-version backup, or another archive, is refused with
a clear message before anything is written.

### Edge Cases

- A backup from a newer app version: refused, "Update the app to read it."
- A backup whose scene, show or preset index is an older format version: migrated by that record's own reader (SCN-013, PRE-012), then restored.
- A backup that names a preset in a collection or favorites that is not in the library (a purchased preset not unlocked here): the identifier is kept; the existing "not available" handling applies.
- A preset in the backup whose text does not match its checksum: the whole backup is refused (FILE-002).
- A restore that would exceed a store's limits (256 cues, 1,000 presets, 100 collections): refused before anything is written, with the limit named.
- Cancel at the preview, or cancelling a pending restore: the library is byte-for-byte unchanged.
- The app is killed during the launch-time restore: the next launch rolls it back or forward.
- An empty library: Back Up Library still writes a valid file with zero counts.

## Requirements *(mandatory)*

### Functional Requirements

- **FILE-005-R1**: Back Up Library writes one archive with the included records of the Baseline, and nothing else; it applies the exclusions (full-library copies, quarantined presets, videos, imported audio, device switches, notices, the entitlement) and reports their counts.
- **FILE-005-R2**: The archive carries a manifest with a format name, a format version, the app version, the creation time, record counts and every entry's path, size and SHA-256; reading verifies all of it before anything is interpreted, with the safety limits of the existing archive reader (entry count, sizes, safe paths, bounded manifest) and the limits in Clarifications (512 MiB file, 4,096 entries, 64 MiB per entry, 1 MiB manifest, 64 photos).
- **FILE-005-R3**: A backup of a newer format version is refused with "update the app"; an older format version is read through a migration table (one row today); records inside are migrated by their own readers.
- **FILE-005-R4**: The backup is offered to the system exporter; the temporary copy is deleted when it closes, saved or cancelled. No copy leaves the device except where the user saves it.
- **FILE-005-R5**: Restore from Backup reads the picked file once, validates it and shows a dry-run preview: per record kind the numbers of new, identical and clashing records, what is left out, and the "Apply to all" choice (Keep both by default, Replace, Skip). Nothing is written by the preview.
- **FILE-005-R6**: Restore records the request (the backup and the choice) and takes effect at the next launch before any store loads; the request can be cancelled until then; its result (the counts actually installed) is shown once in Settings › Storage and announced.
- **FILE-005-R7**: At launch the restore plans again against the library with the recorded choice and installs all or nothing: every changed folder is built in a staging area and verified, swapped in under a journal, and settings applied after the commit point; any failure before the commit restores the library byte for byte; an interrupted restore is rolled back or completed at the next launch.
- **FILE-005-R8**: Into a library with none of the backup's records, the restore recreates every included record exactly (FILE-005-R9's comparison).
- **FILE-005-R9**: "Exact logical records" is one function over a library: the show (canonical bytes), each stored scene (canonical bytes by ID), the current scene (canonical bytes), each included preset (identifier, name, author, file name, text, license, origin, import and edit dates; not the check state), the collections (canonical bytes, order kept), each included setting (typed value), the favorites set, the last preset and each photo (bytes). Two libraries are equal when the function's results are equal; it is tested.
- **FILE-005-R10**: Clashes follow FILE-004: Skip leaves the device's record byte-identical; Replace keeps the device's identifier and takes the backup's content; Keep both adds the backup's record under a derived identifier (deterministic: the same backup and library give the same identifiers) and a copy name. Single-valued records under Keep both keep the device's value; favorites are the union.
- **FILE-005-R11**: Restored presets wait for their check (PRE-012); no backup can mark a text as checked.
- **FILE-005-R12**: The two actions live in Settings › Storage under "Backup", with text that wraps at accessibility sizes; announcements go through the shared announcer's `library` lane; nothing animates.
- **FILE-005-R13**: No networking, nothing from a backup executed, no new permission, public APIs only; the privacy policy says that a backup is made only when the user asks and goes only where the user saves it.

### Key Entities

- **Library backup**: the archive file; its manifest (format, version, app version, created at, counts, exclusions, file list).
- **Library records**: the logical view of a library (FILE-005-R9), keyed by record ("scene/<ID>", "preset/<id>", "setting/<key>", …).
- **Restore plan**: per record its kind (new, identical, clash), the effective choice, the outcome, and whether Keep both fell back to keeping the device's value.
- **Restore request**: the pending backup and choice, applied at the next launch.
- **Restore journal**: the commit point of a running restore.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FILE-005-S1**: Backup then restore into an empty sandbox gives equal logical records for 100% of the included records of a fixture library holding every record kind.
- **FILE-005-S2**: A fault at each file operation of a restore leaves the library snapshot identical every time; an interrupted restore is finished or rolled back at the next launch.
- **FILE-005-S3**: Each choice (Skip, Keep both, Replace) over a clashing library gives the outcome of FILE-005-R10, and planning twice gives identical plans.
- **FILE-005-S4**: 100% of corrupt, truncated, tampered, oversize, foreign and newer-version fixtures are refused before anything is written; the fuzz suite runs the backup reader with no crash or hang within its budget.
- **FILE-005-S5**: No backup of a fixture library contains a full-library preset copy, a quarantined text, a video, imported audio or an entitlement.
- **FILE-005-S6**: A simulator UI test backs up a library to a test folder, restores it into a reset library across a relaunch and finds the records back, in under 30 seconds per test.

## Assumptions

- FILE-001/002's archive layer (stored ZIP, checksummed manifest, bounded JSON), FILE-003's snapshot and FILE-004's derived identifiers and scene installer are the base.
- The backup is read into memory; backups larger than the cap (512 MiB) are refused.
- Simulator results prove behaviour only, never performance.

## Out of Scope

- Videos and imported audio in the backup, incremental backups (FILE-006).
- Per-record choices in the preview (the plan supports overrides; the screen offers "Apply to all").
- Encrypting the backup, iCloud or any automatic backup.
- Erasing data (FILE-011).
