# Feature Specification: FILE-010 Safe Cache Cleanup

**Feature Branch**: `feature/file-010` (spec directory `072-file-010-safe-cache-cleanup`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (FILE-010-T01-T10 verified on the Mac host and an iOS 27.2 simulator; T11 `{device}` open)

**Input**: User description: "Implement FILE-010 (Safe cache cleanup) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Clear generated previews and
intermediates without touching user data." Acceptance, verbatim: "Cleanup removes cache only and all
saved scenes remain loadable." P0, effort S, depends on FILE-009."

Identifiers in this feature carry the roadmap ID: requirements `FILE-010-R1…`, success criteria
`FILE-010-S1…`, tasks `FILE-010-T01…`. Other features are cited by their own IDs: FILE-009 (storage
usage explorer), MED-001 (photo), MED-002 (video), SCN-001 (scene document), SCN-002 (scene autosave),
SHOW-001 (cue list and its scene snapshots), PRE-007 (collections), PRE-012 (user presets), AUD-001
(imported audio), REC-003 (recordings), REC-012 (share copies and the offered recording), FILE-001
(scene archive export), PRE-014 (preset export), FILE-011 (local data erase).

## Baseline: what is cache and what is user data (audit of 2026-11-13, commit `578cac5`)

FILE-009's Storage screen measures these folders. FILE-010 classifies each one.

| Store | Folder | FILE-009 category | FILE-010 class |
|---|---|---|---|
| MED-001 photo | `Library/Application Support/Photos` | Photos | User data: never touched |
| MED-002 video | `Library/Application Support/Videos` | Videos | User data: never touched |
| SCN-002 autosave (current, backup) | `Library/Application Support/Scenes` | Scenes | User data: never touched |
| SHOW-001 show and its scene snapshots | `Library/Application Support/Show` | Other app data | User data: never touched |
| PRE-012 user presets | `Library/Application Support/UserPresets` | Presets | User data: never touched |
| PRE-007 collections | `Library/Application Support/PresetCollections` | Presets | User data: never touched |
| AUD-001 imported audio | `Library/Application Support/AudioLibrary` | Imported audio | User data: never touched |
| Settings (preferences) and everything else | rest of the container | Other app data | Never touched |
| REC-003 recordings | `tmp/Recordings` | Recordings | Intermediate: cleared unless in use |
| REC-012 share copies | `tmp/Sharing` | Shares and exports | Intermediate: cleared unless in use |
| FILE-001 scene archive export | `tmp/SceneArchiveExport` | Shares and exports | Intermediate: cleared unless in use |
| PRE-014 preset export | `tmp/PresetExport` | Shares and exports | Intermediate: cleared unless in use |
| System caches (compiled shaders) | `Library/Caches` | Caches | Cache: cleared |

"Generated previews" in the roadmap row are the share copies and exports made for the share sheet;
the app keeps no thumbnail or preview files on disk (previews are drawn in memory).

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Does Clear Caches empty `Library/Caches`, which only the system writes (compiled shaders)? →
  A: Yes. Apple documents it as purgeable at any time, it is the "Caches" row the person sees, and the
  cost is a shader recompile on the next preset switch; the confirmation says nothing about speed
  because the effect is a one-time short delay. Applied to FILE-010-R1 and the baseline.
- Q: Are leftover recordings in `tmp/Recordings` cleared? → A: Yes, unless in use: everything in
  Recordings is kept while a recording is being made or finished, and the offered recording (and one
  handed to the Save mover) is kept file by file, so a result the person has not yet saved, shared or
  discarded never disappears. Other files there are leftovers. Applied to FILE-010-R5.
- Q: Which number does the confirmation state? → A: The space used by the items to be removed
  (allocated blocks), the same measure the Storage screen shows (FILE-009 clarification), formatted
  the same way; "about" when the plan hit a walk limit. Applied to FILE-010-R2.
- Q: Is cleaned data recoverable (a trash or undo)? → A: No. Only caches and intermediates are
  removed, which the app or the system recreates; a trash would keep the space the person wants back.
  The confirmation is the safeguard. Applied to FILE-010-R2.
- Q: Should the app clear caches on its own (at launch or under storage pressure)? → A: No. Only on
  the person's request from the Storage screen; the existing launch-time cleanup of Recordings and
  Sharing by their owners is unchanged. Applied to Scope.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Free the space caches take (Priority: P1)

A performer whose device is nearly full opens Settings › Storage, sees that caches, leftover recordings
and share copies take space, taps Clear Caches, reads how much will be freed and what is kept, confirms,
and sees those categories drop while their photos, videos, scenes, show, presets and audio stay.

**Why this priority**: The row's observable behavior.

**Independent Test**: Seed caches and user data, clear, compare.

**Acceptance Scenarios**:

1. **Given** cache and intermediate files in Recordings, Shares and exports and Caches, **When** the
   person taps Clear Caches, **Then** a confirmation states the space to be freed and that photos,
   videos, scenes, the show, presets, imported audio and settings are kept.
2. **Given** the confirmation, **When** the person confirms, **Then** those files are removed, the
   screen measures again, and Recordings, Shares and exports and Caches show zero while every other
   category is unchanged.
3. **Given** the confirmation, **When** the person cancels, **Then** nothing is removed.
4. **Given** nothing to clear, **When** the person taps Clear Caches, **Then** the screen says there is
   nothing to clear and removes nothing.

### User Story 2 - User data is never touched (Priority: P1)

Cleanup never removes, changes or moves user data, and every saved scene still loads afterwards.

**Why this priority**: The row's acceptance: "Cleanup removes cache only and all saved scenes remain
loadable."

**Independent Test**: A fixture container with user data and caches; after cleanup every user file is
byte-identical and the current scene, its backup and the show's scene snapshots load.

**Acceptance Scenarios**:

1. **Given** user data and caches, **When** cleanup runs, **Then** every user-data file is
   byte-identical and the current scene, the backup scene and each show scene load.
2. **Given** a link inside a cache folder that points at user data, **When** cleanup runs, **Then** the
   link is removed and the data it pointed at is untouched.
3. **Given** a folder that is not one of the cache folders (or a cache folder that is a link, lies
   outside the app's container, or contains a user-data folder), **When** cleanup is planned, **Then**
   it is refused and nothing in it is removed.

### User Story 3 - Files in use are kept (Priority: P2)

A recording being made or offered (Save, Share, Discard), a share copy on show, or an export being
written is never removed.

**Independent Test**: Mark a recording as in use and clear: it stays; a leftover recording beside it goes.

**Acceptance Scenarios**:

1. **Given** a recording offered after Stop and a leftover from an earlier session, **When** cleanup
   runs, **Then** the offered recording stays and the leftover is removed.
2. **Given** a recording in progress, **When** cleanup runs, **Then** nothing in Recordings is removed.

### Edge Cases

- A cache folder that does not exist: nothing to do, not an error.
- An item removed by someone else between planning and clearing: skipped silently.
- An item that cannot be removed: the rest are still removed; the screen says some files could not be
  removed and the new sizes show what is left.
- A folder replaced by a link between planning and clearing: the link is removed, never followed.
- The person leaves the screen while clearing: clearing finishes (it is short); the result is not shown.
- Very deep or very large cache folders: planning stops at FILE-009's walk limits; items beyond them
  are still removed with their folder, but the bytes shown are "at least".

## Requirements *(mandatory)*

### Functional Requirements

- **FILE-010-R1**: The Storage screen MUST offer Clear Caches, which clears only the cache and
  intermediate folders named in the baseline (Recordings, the three share and export folders, and
  Caches).
- **FILE-010-R2**: Before clearing, the screen MUST ask for confirmation, stating the space to be freed
  (the space used by the items to be removed, prefixed "about" when a walk limit was reached) and that photos, videos, scenes, the show, presets,
  imported audio and settings are kept; Cancel removes nothing. With nothing to clear it MUST say so
  and offer no Clear button.
- **FILE-010-R3**: Cleanup MUST use an allowlist: it removes items only inside the cache and
  intermediate folders, and refuses a folder that is not on the list, that is a link, that is or lies
  outside the app's container, or that contains or lies inside a user-data folder.
- **FILE-010-R4**: Cleanup MUST NOT follow links: a link inside a cache folder is removed as a link,
  and the data it points at is untouched. Before removing an item it MUST check that the item is still
  inside its cache folder and that no folder above it has become a link.
- **FILE-010-R5**: Cleanup MUST keep files in use: while a recording is being made or finished, all of
  Recordings; an offered recording and one handed to the Save mover; a share copy on show; and the
  preset export folder while an export is written, plus the exported file while its share sheet shows.
  Folders containing a kept file stay, with their other contents removed.
- **FILE-010-R6**: Planning and clearing MUST run off the main thread; afterwards the screen MUST
  measure again and show the new sizes; while clearing, Clear Caches and Refresh are disabled.
- **FILE-010-R7**: Cleanup MUST NOT read file dates or volume free space (privacy manifest), MUST NOT
  touch preferences, and MUST send nothing off the device.
- **FILE-010-R8**: The planning and clearing logic MUST be plain Swift behind a replaceable file system,
  so it is tested on the Mac host and on Linux.
- **FILE-010-R9**: If some items cannot be removed, cleanup MUST continue with the rest and the screen
  MUST say "Some files could not be removed."

### Key Entities

- **Cleanup plan**: the items to remove (path, kind, category, bytes), the refused folders, the kept
  in-use items, and the space to be freed.
- **Cleanup result**: the items removed, the items that failed, the space freed.
- **In-use set**: paths the running app must keep, gathered when Clear Caches is tapped.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FILE-010-S1**: For a fixture container with a photo, a video, a current scene and its backup, a show
  with two scene snapshots, user presets, a collection and imported audio, plus caches in all five
  cache folders and a leftover recording: after cleanup 100% of user-data files are byte-identical, the
  current scene, the backup and both show scenes load with the app's own loaders, and every cache item
  is gone except the in-use recording.
- **FILE-010-S2**: A link in a cache folder to user data is removed and its target is byte-identical.
- **FILE-010-S3**: The planner refuses each of: a non-allowlisted category, a link root, the container
  itself, a root outside the container, a root containing a user-data folder.
- **FILE-010-S4**: On the simulator, Settings › Storage › Clear Caches › Clear makes Recordings, Shares
  and exports and Caches show zero while Photos, Videos, Scenes, Presets and Imported audio keep their
  values.
- **FILE-010-S5**: Unit tests run in about 1-2 s each (at most 10 s), the UI test in under 30 s.

## Assumptions

- `Library/Caches` holds only what the system may purge at any time; removing it is safe and costs at
  most a shader recompile on the next preset switch.
- Unlinking a file another part of the app has open is safe on the device's file system; in-use rules
  exist so a visible result (an offered recording, a shown share) never disappears.
- The scene archive import staging folder (`tmp/SceneArchiveImport`) is owned by an import while it
  runs and is outside FILE-009's categories; it is not cleared here.

## Scope

| In this row | Later rows / follow-ups |
|---|---|
| Clear Caches on the Storage screen, allowlist plan, in-use protection, tests | FILE-011 erases selected user data |
| On request only | No automatic clearing at launch or under storage pressure (clarification) |
| | Device check on D1 with a real shader cache (`{device}` task, left open) |
