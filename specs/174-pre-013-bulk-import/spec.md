# Feature Specification: PRE-013 Bulk Preset Import

**Feature Branch**: `feature/pre-013` (spec directory `174-pre-013-bulk-import`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row PRE-013 (P1, size L, depends on PRE-012). Observable behavior, verbatim: "Import
a folder or archive with progress and duplicate detection." Acceptance, verbatim: "Fixture of 100 files
reports exact added/skipped counts."

Identifiers carry the roadmap ID: requirements `PRE-013-R1…`, success criteria `PRE-013-S1…`, tasks
`PRE-013-T01…`. Other features are cited by their own IDs: PRE-012 (single preset import, the user preset
store, quarantine, the off-screen trial and the on-screen guard), PRE-014 (user preset export archive),
PRE-002 (thumbnail invalidation), PRE-003 (tags), FILE-003 and FILE-004 (preset archive preview and
conflict resolver), QA-005 (import fuzz suite), ACC-004 and FILE-003-R13 (announcements on the library
lane).

## Baseline: what exists today (audit of 2026-11-14, commit `5aaeebe5`)

| Area | Today |
|---|---|
| Single import (PRE-012) | "Import Preset…" in My Presets picks one `.milk` file. `UserPresetLibrary.importFile` reads at most 512 KiB + 1 byte (no symlinks, regular files only, `.milk` only), hashes it (SHA-256 and git blob SHA-1), refuses duplicates of imported, quarantined and built-in presets and takedown-listed hashes, runs `MilkdropPresetValidator` (a rejection is stored in quarantine), stores the copy content-addressed, then runs the off-screen trial. |
| Store | `UserPresetStore`: content-addressed `files/<sha256>.milk`, a versioned `index.json`, every file operation behind a path guard; `commitImport` (FILE-003/004) adds several presets all or nothing through `staging/`. Caps: 1,000 waiting or playable presets, 200 quarantined. |
| On-screen guard | `userGuard` (`willShow`/`didShow`/`stoppedShowing`/`failedOnScreen`) proves an imported preset during its first 3 s on screen; only playable presets reach a renderer. |
| Archives (FILE-003/004, PRE-014) | A `.zip` picked in "Import Preset…" must be a PRE-014 preset archive (a `manifest.json` plus `presets/…`); it is previewed and installed all or nothing. The ZIP reader (`LocalPortability.StoredZipReader`) reads stored entries only and refuses the whole archive on any unsafe path, link, compressed entry or comment. |
| Thumbnails (PRE-002) | `UserPresetsCoordinator.refresh` invalidates thumbnails of playable presets whose text changed; new presets simply have none yet. |
| Tags (PRE-003) | Tags are user-curated per preset id; removing a user preset prunes its tags. |
| Fuzzing (QA-005) | `ImportFuzz` mutates presets and archives through the PRE-012 validator and the archive readers. |
| Gap | No way to import many `.milk` files at once: a folder of presets, or an ordinary `.zip` of `.milk` files (most collections are shared that way), takes one picker round per file, and an ordinary `.zip` is refused as "not a preset archive". |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option that delivers the roadmap row.

- Q: Where does the user start a bulk import? → A: A new "Import Folder or Archive…" action in My Presets, next to "Import Preset…". It opens the system Files picker for one folder or one `.zip` file. The picked folder is read in place, read-only, under its security scope; nothing in it is changed. "Import Preset…" keeps its behavior (one `.milk`, or a PRE-014 preset archive into the FILE-003 preview).
- Q: What does a `.zip` mean here? → A: An ordinary archive of files, read like a folder: its entries are the files. A PRE-014 `manifest.json` in it is just a non-preset file. Stored and deflate-compressed entries are read; encrypted entries, other compression methods, links and special files are listed as unsupported. Unlike FILE-003, one bad entry does not refuse the whole archive; it is listed and skipped.
- Q: What is imported? → A: Only regular files named `*.milk` (any letter case), each within the PRE-012 size limit (512 KiB) and passing the PRE-012 static checks. Everything else is listed with its reason and skipped.
- Q: What does each file end up as? → A: Exactly one of: **added**; **skipped, duplicate**; **skipped, invalid** (the static checks reject it, it is empty, or its content is on the takedown list); **skipped, too large**; **skipped, unsupported** (not a `.milk` file, a link, an unsafe archive path, an unreadable compression method); **failed** (it could not be read or saved, or My Presets is full). The summary gives the exact count of each, and a per-file list gives each file's outcome and reason.
- Q: What is a duplicate? → A: The same bytes (SHA-256) as a preset already in My Presets (any state, quarantined included), as an earlier file in the same import, or (git blob hash) as a built-in preset of any pack. Names do not matter: two files with different names and the same bytes are duplicates; two files with the same name and different bytes are both added.
- Q: Are invalid files quarantined, as a single import does? → A: No. A bulk import skips them and says why in the list; nothing about them is stored. Quarantine stays for a preset the user imported on purpose one at a time, and for presets that fail their engine trial later. This keeps a large folder from filling the 200-file quarantine with noise.
- Q: What are the bounds? → A: At most 2,000 files per import (counting every file found, any type); at most 64 MiB of candidate `.milk` bytes in total; folders at most 8 levels below the picked folder; archives at most 64 MiB. A folder or archive over the file count or byte total is refused before anything is imported, with the reason. Deeper folders are not opened (their count is reported). Symbolic links are never followed. Hidden files and folders (name starting with ".") and `__MACOSX` folders are system metadata, not files the user chose: they are not opened or listed, and their count is reported.
- Q: Progress and Cancel? → A: A progress view shows "n of N files" and the running counts, with Cancel. Cancel is atomic per file: the file being handled finishes or is not started, every file already added stays added, and the run stops. The summary of a cancelled run gives the exact counts of the files handled and says how many were not handled.
- Q: Does an added preset play at once? → A: It is added the way an archive install adds one (FILE-003): waiting for its off-screen engine trial, which runs after the import, so the PRE-012 guards (trial, proving period, quarantine) apply unchanged. "Added" counts presets stored in My Presets; a trial that later quarantines one is PRE-012's existing behavior.
- Q: Folder name as a tag (PRE-003)? → A: No. Tags stay user-curated; a folder name from another source is not a tag the user chose. The summary names the folder instead.
- Q: Announcements? → A: On the shared announcer's library lane: one at the start ("Importing <name>: <N> files."), progress at most at each quarter (25, 50, 75 %), and the summary at the end (or "Import cancelled. …").

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Is a second copy of a file that was itself skipped (invalid, too large) a duplicate? → A: A duplicate is decided on bytes for every file that reached hashing (not unsupported, not too large, readable, not empty): a second copy of an invalid file is a duplicate of the first, so each content is judged and reported once. Too-large and unsupported files are never hashed.
- Q: What if the app ends during an import (crash, force quit)? → A: Added presets are saved in batches of at most 50 files, each batch all or nothing (the FILE-003 staged commit). Batches saved before the end stay; the files of an unsaved batch are simply not in My Presets (no partial file, no record without its text). Importing the folder again adds them and reports the rest as duplicates.
- Q: In which order are files handled and listed? → A: In path order (byte-wise, so it is the same on every device and locale); the per-file list keeps that order and can be filtered to the skipped and failed files.
- Q: Is the summary kept after the sheet closes? → A: No. It is shown once (sheet and announcement) and kept in memory until the next import; nothing about the run is written to disk (no log of file names).
- Q: What if an added preset's name equals an existing preset's name? → A: Both are kept, as with a single import (PRE-012): names are not unique; identical bytes are what make a duplicate.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Import a folder of presets in one go (Priority: P1) — MVP

A VJ has a folder of 100 presets collected over the years, with some copies, a few broken files and
some notes and images. They choose "Import Folder or Archive…", pick the folder, watch the progress,
and get a summary: how many were added and why each other file was skipped.

**Why this priority**: It is the row's behavior and acceptance.

**Independent Test**: The 100-file fixture (70 valid and unique, 10 copies of others in the batch, 5
copies of presets already in My Presets, 8 the checks reject, 4 over the size limit, 3 non-preset
files) imported from a folder reports added 70, skipped duplicates 15, invalid 8, too large 4,
unsupported 3, failed 0; My Presets then holds exactly the 70 new presets plus the ones it had.

**Acceptance Scenarios**:

1. **Given** My Presets holds 5 presets, **When** the fixture folder is imported, **Then** the summary says added 70, skipped 30 (15 duplicates, 8 invalid, 4 too large, 3 unsupported), failed 0, and My Presets holds exactly 75 presets: the 5 and the 70 new ones.
2. **Given** the same, **When** the per-file list is shown, **Then** it has exactly 100 rows, one per file, each with its outcome and reason.
3. **Given** the import finished, **When** the trials run, **Then** the new presets become playable or are quarantined by PRE-012's existing rules.

### User Story 2 - Import a `.zip` of presets (Priority: P1)

The same collection shared as an ordinary `.zip` (as most preset packs are) is imported the same way.

**Independent Test**: The fixture packed as a `.zip` gives the same counts as the folder.

**Acceptance Scenarios**:

1. **Given** the fixture as a `.zip` (stored or deflate entries), **When** it is imported, **Then** the counts equal the folder's.
2. **Given** an archive with an entry named `../evil.milk` or `/abs.milk`, **When** it is imported, **Then** that entry is skipped as unsupported ("outside the archive's folder"), nothing is written outside My Presets' own store, and the other entries are handled normally.

### User Story 3 - Cancel a long import (Priority: P2)

The user starts a large import and cancels part way.

**Independent Test**: Cancel after N files; the files already added are in My Presets, the summary's
counts add up to the files handled, and the rest are reported as not handled.

**Acceptance Scenarios**:

1. **Given** an import of 100 files, **When** Cancel is requested after the 30th file, **Then** the summary counts exactly 30 handled files, every file counted as added is in My Presets and no other new preset is, and 70 are reported as not handled.
2. **Given** a cancelled import, **When** the same folder is imported again, **Then** the presets added the first time are reported as duplicates and the rest are added.

### Edge Cases

- The folder or archive has more than 2,000 files or more than 64 MiB of preset bytes: refused before anything is imported, with the reason; My Presets unchanged.
- An empty folder, or one with no `.milk` file: the summary says nothing was added and lists the other files.
- My Presets fills up (1,000) during the import: the remaining valid presets are listed as failed ("My Presets is full").
- The saved record is from a newer app version: the action is disabled, as for a single import.
- A file disappears or cannot be read during the import: that file is failed ("could not be read"); the rest continue.
- A symbolic link in the folder: listed as unsupported and never followed.
- A file named `.milk` with upper-case extension (`A.MILK`): treated as `.milk`.
- Another import or an export is running: the action is disabled.
- An archive entry nested more than 8 path components deep is listed as unsupported ("too deeply nested"); in a folder, such folders are not opened and only counted.
- The app ends during an import: the batches saved before stay; the unsaved batch leaves nothing behind.

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-013-R1**: My Presets MUST offer "Import Folder or Archive…", which opens the system picker for one folder or one `.zip` file; a cancelled picker changes nothing. It is disabled while another import, archive install or export runs, and when the record is from a newer version.
- **PRE-013-R2**: A picked folder MUST be read in place under its security scope and never written to. Symbolic links MUST NOT be followed; folders more than 8 levels below the picked folder MUST NOT be opened; hidden entries and `__MACOSX` folders MUST NOT be opened or listed. Counts of folders not opened and of hidden entries are reported.
- **PRE-013-R3**: A picked `.zip` MUST be read as an ordinary archive of files: stored and deflate entries; per-entry problems (an unsafe path such as `../x` or `/x`, a link or special file, encryption, another compression method) MUST skip that entry with its reason, and a damaged entry (checksum or size mismatch) MUST be failed; neither refuses the archive. A file that is not a readable ZIP, or over 64 MiB, is refused as a whole.
- **PRE-013-R4**: Before anything is imported, an import with more than 2,000 files or more than 64 MiB of candidate `.milk` bytes MUST be refused with the reason, and nothing stored.
- **PRE-013-R5**: Each file MUST end as exactly one of added, skipped duplicate, skipped invalid, skipped too large, skipped unsupported, or failed, decided in this order: unsupported (not a regular `.milk` file, unsafe path, unreadable method), too large (over 512 KiB), failed (unreadable), invalid (empty), duplicate (same bytes as a preset in My Presets, an earlier file in this import, or a built-in preset), invalid (takedown list, or rejected by the PRE-012 static checks), failed (My Presets full, or could not be saved), else added.
- **PRE-013-R6**: An added preset MUST be stored exactly as a FILE-003 archive install stores one: a content-addressed copy, waiting for its off-screen trial, with the name and author taken from its file name (PRE-012 rules) and the validator's warnings and licence lines; after the import the waiting trials run. Invalid files MUST NOT be stored or quarantined.
- **PRE-013-R7**: The import MUST run off the main thread; the screen stays responsive and shows "n of N files" with the running counts and a Cancel button.
- **PRE-013-R8**: Cancel MUST be atomic per file: every file counted as added is in My Presets, no file not counted as added is, and the counts cover exactly the files handled; the number not handled is reported.
- **PRE-013-R9**: The result MUST give the exact counts of the six outcomes, the files not handled, and a per-file list (path inside the folder or archive, outcome, reason), shown in a summary sheet with a one-line summary text.
- **PRE-013-R10**: Announcements MUST go through the shared announcer's library lane: the start, progress at most at 25, 50 and 75 %, and the summary (or the cancelled summary).
- **PRE-013-R11**: Nothing from a file's name or location MUST be used as a storage path (PRE-012-R4); every store write stays behind the store's path guard.
- **PRE-013-R12**: Imported presets MUST NOT be tagged automatically; thumbnails follow PRE-002 unchanged.
- **PRE-013-R13**: Added presets MUST be saved in batches of at most 50 files, each all or nothing; files are handled and listed in byte-wise path order; a second copy of any hashed file (whatever the first copy's outcome) is a duplicate.
- **PRE-013-R14**: Nothing about a run (file names, counts) MUST be written to disk; the report lives in memory until the next import.

### Key Entities

- **Bulk import source**: a picked folder or `.zip`; its candidate files with their paths inside it and sizes.
- **Bulk import item**: one file's path, outcome (six kinds) and reason.
- **Bulk import report**: counts per outcome, files not handled, folders not opened, hidden entries, cancelled flag, the item list, and the summary text.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-013-S1**: The 100-file fixture imported from a folder reports exactly added 70, duplicates 15, invalid 8, too large 4, unsupported 3, failed 0, and My Presets gains exactly the 70 new presets (acceptance).
- **PRE-013-S2**: The same fixture as a `.zip` reports the same counts.
- **PRE-013-S3**: A run cancelled after N files reports N handled files whose counts add up to N, and My Presets gains exactly the files counted as added.
- **PRE-013-S4**: Archive entries with unsafe paths are skipped and nothing is written outside the store.
- **PRE-013-S5**: A UI test imports a small fixture folder and reads the summary text in under 30 s.

## Assumptions

- The system picker supplies folder and file URLs with a security scope; the app reads them only during the import.
- Deflate entries are inflated with the platform's public compression API; on a platform without it (Linux tests) deflate entries are listed as unsupported.
- Trials, proving and quarantine after the import are PRE-012's and unchanged.
