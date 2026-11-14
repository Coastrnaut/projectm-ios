# Feature Specification: REC-010 Recording library

**Feature Branch**: `feature/rec-010` (spec directory `198-rec-010-recording-library`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement REC-010 (Recording library) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "List and manage local recordings with preview and file size." Acceptance,
verbatim: "Delete removes file after confirmation and updates list immediately." P1, M, depends on REC-003
(integrated); REC-004 to REC-009, REC-012, REC-015, FILE-009, FILE-010, FILE-011 and QA-008 are integrated too."

Identifiers carry the roadmap ID: requirements `REC-010-R1…`, success criteria `REC-010-S1…`, tasks
`REC-010-T01…`, research decisions `REC-010-D1…`.

## Baseline: what exists today (audit of 2026-11-14, commit `a06828fa`)

| Area | Today |
|---|---|
| Where a recording is written | REC-003 `VideoRecordingCoordinator` writes `<tmp>/Recordings/Visualizer Recording <yyyy-MM-dd at HH.mm.ss>.mp4` (HEVC or H.264, optional AAC track). |
| After the finish | REC-012 offers the file ("Recording ready": Save…, Share…, Discard). Save… opens the system file mover (the file is moved out of the app); Share… hands a temporary copy in `<tmp>/Sharing/<UUID>/` to the share sheet; Discard deletes it. While a recording is offered, Record refuses. |
| What is kept | Nothing: leftovers in `<tmp>/Recordings` are deleted at the next launch (REC-003-R13). No recording outlives the session inside the app container. |
| Photos | The app declares no Photos library permission (`PermissionCatalog.photosLibrary`); Save to Photos is excluded from the share sheet (REC-012-R7). |
| FILE-009 storage | Nine categories; `Recordings` = `<tmp>/Recordings` (cleanable by FILE-010 Clear Caches). |
| FILE-010 cleanup | Clears `Recordings`, `Shares and exports` and `Caches`, never the user-data categories, never files in use. |
| FILE-011 erase | Six categories (scenes, presets, collections, media, imported audio, settings) under Application Support; none for recordings. |
| Read-back | `RecordedVideoInspector` (codec, size, frames, duration, tracks; reads every compressed sample) and QA-008 `RecordingValidator` (also decodes the audio). |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: How does a recording get into the library, given that today nothing is kept? → A: Only by the user's choice: the "Recording ready" panel gains a fourth action, **Keep**, which moves the offered file into the app's recording library folder (`Application Support/RecordingLibrary`). Save…, Share… and Discard are unchanged, and a recording that is not kept is still deleted at the next launch. Keeping every recording automatically would silently fill storage and change REC-003-R13's "nothing outlives the session".
- Q: Where is the library shown? → A: Settings › Storage › **Recordings** (a link with the number of saved recordings), next to the storage totals it affects.
- Q: Is the list backed by an index? → A: No. The list is a scan of the library folder each time the screen opens and after each change; there is no database to drift from the files.
- Q: Is Rename in scope? → A: Yes: a validated new name (not empty, no "/" or ":", not starting with ".", at most 100 characters, unique in the folder); the extension is kept.
- Q: Is Save to Photos offered? → A: No. The app declares no Photos permission (a constitution-checked catalog rule); Share… offers Save to Files and other apps, as REC-012 does.
- Q: How is an incomplete or unreadable file shown? → A: As "Incomplete" with Delete as its only action. Only kept (finished) files enter the library, so this covers a damaged or truncated file.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Are a row's facts read with the full QA-008 read-back or a quick read of the file's header? → A: A quick header read (duration, video track size, nominal frame rate, codec): QA-008's validator decodes the audio and reads every sample, which is too slow for a list. A file whose header cannot be read, or that has no video track or no duration, is "Incomplete" (REC-010-R4).
- Q: Where are thumbnails cached and what clears them? → A: In memory for the screen's life and as small JPEG files in `Library/Caches/RecordingThumbnails`, keyed by the file name and byte size (a rename or a changed file makes a new entry). Delete and rename remove the old entry; FILE-010 Clear Caches may remove them all; they are made again on the next visit.
- Q: When does the list rescan the folder? → A: When the screen appears and after each Keep, delete or rename in it; a delete removes the row from the model in the same update before the rescan, so the count never shows the deleted file.
- Q: How does VoiceOver read and act on a row? → A: One element per row: "<name>, <duration>, <size>, <date>, <resolution>, <frame rate>, <codec>" (or "<name>, Incomplete, <size>"), with Play, Share, Rename and Delete as accessibility actions (Delete only for an incomplete file). Results ("Recording deleted.", "Recording renamed.", "Recording kept in Recordings.") are announced on the library lane.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Keep and browse recordings (Priority: P1)

A performer records several takes, keeps the good ones and later opens Settings › Storage › Recordings to
see them newest first, each with a preview picture, length, size, date, resolution, frame rate and codec.

**Why this priority**: It is the roadmap row ("list … with preview and file size").

**Independent Test**: Three generated recordings in the library folder appear newest first with their facts and
a thumbnail; a kept offered recording appears in the list.

**Acceptance Scenarios**:

1. **Given** a recording is offered, **When** the user taps Keep, **Then** the file is moved into the library, the offer closes and "Recording kept in Recordings." is shown and announced.
2. **Given** three saved recordings, **When** the Recordings screen opens, **Then** they are listed newest first, each with thumbnail, duration, file size, date, resolution, frame rate and codec, and the header shows the count and total size.
3. **Given** a file that cannot be read as a video, **When** the list shows, **Then** its row reads "Incomplete" with its size and only Delete is offered.

---

### User Story 2 - Delete a recording (Priority: P1)

The user removes a take they no longer want.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Seed three recordings, delete the middle one and confirm: the file is gone, the list shows two at once and the totals drop by its size; cancelling keeps the file.

**Acceptance Scenarios**:

1. **Given** three recordings, **When** the user chooses Delete on one, **Then** a confirmation names it and says it cannot be undone.
2. **Given** the confirmation, **When** the user confirms, **Then** the file is removed from disk, the list shows the other two immediately, the header and Storage totals drop by its size, its cached thumbnail is removed, and "Recording deleted." is announced.
3. **Given** the confirmation, **When** the user cancels, **Then** the file and the list are unchanged.

---

### User Story 3 - Play, share and rename (Priority: P2)

The user plays a saved take in the app, shares it, or gives it a clearer name.

**Independent Test**: Unit tests for rename validation and the share request; the player is opened for the row's file.

**Acceptance Scenarios**:

1. **Given** a saved recording, **When** the user taps Play, **Then** an in-app player plays the local file.
2. **Given** a saved recording, **When** the user taps Share…, **Then** the system share sheet offers the file, without Save to Photos or Assign to Contact.
3. **Given** a saved recording, **When** the user renames it to a valid unused name, **Then** the file is renamed (extension kept) and the list updates; an invalid or taken name is refused with a message and nothing changes.

### Edge Cases

- Keep when a file of that name already exists in the library: the kept file gets " 2", " 3"… before the extension.
- The library folder does not exist yet: the list is empty ("No saved recordings").
- Delete of a file that is already gone: the row is removed and the list rescanned; no error is left on screen.
- A recording shorter than 1 s: the thumbnail is taken at half its duration.
- Clear Caches (FILE-010) never removes saved recordings; it may remove cached thumbnails, which are made again.
- Erase Data (FILE-011) with "Saved recordings" checked removes the library folder at the next launch.
- Hidden files (names starting with ".") are not listed.

## Requirements *(mandatory)*

### Functional Requirements

- **REC-010-R1**: The "Recording ready" panel MUST offer Keep, which moves the offered file into the library folder (a new unique name on collision), ends the offer and reports "Recording kept in Recordings." A failed move MUST leave the recording offered with a failure notice.
- **REC-010-R2**: Settings › Storage MUST offer a Recordings screen listing the library folder's non-hidden regular files, newest first (file modification date, then name), scanned from the folder with no separate index.
- **REC-010-R3**: Each readable row MUST show a thumbnail (the frame at 1 s, or at half the duration when shorter), the duration, the file size, the date, the resolution, the frame rate and the codec. Facts MUST come from a quick header read; thumbnails MUST be made off the main thread and cached in memory and in `Caches/RecordingThumbnails` keyed by name and size.
- **REC-010-R4**: A file that cannot be read as a video MUST be listed as "Incomplete" with its size and Delete only.
- **REC-010-R5**: Delete MUST ask for confirmation naming the recording; on confirm it MUST remove the file, remove the row in the same update, update the count and total, and remove the thumbnail cache entry; Cancel MUST change nothing.
- **REC-010-R6**: Play MUST open an in-app player for the local file; Share… MUST present the system share sheet with the file, excluding Save to Photos and Assign to Contact; Rename MUST validate the name (REC-010 Clarifications) and keep the extension.
- **REC-010-R7**: FILE-009 Storage MUST show a "Saved recordings" category (the library folder), not cleanable by FILE-010; the temporary category MUST read "Unsaved recordings".
- **REC-010-R8**: FILE-011 Erase MUST offer a "Saved recordings" category that removes the library folder. Saved recordings MUST NOT be part of a FILE-005 library backup.
- **REC-010-R9**: Keep, delete and rename results MUST be announced on the announcer's library lane; every row MUST be one VoiceOver element reading its name, facts (or "Incomplete") with its actions as accessibility actions too.
- **REC-010-R10**: Nothing MUST leave the device except through the share sheet the user opens; no networking, no new permission, no new stored setting.

### Key Entities

- **Saved recording**: a file in the library folder; name, size, date and, when readable, duration, resolution, frame rate and codec.
- **Thumbnail cache entry**: a small picture of a saved recording keyed by its name and size.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **REC-010-S1**: With three seeded recordings, deleting the middle one after confirmation removes its file, leaves two rows in the same update, and lowers the library total and the Storage "Saved recordings" total by exactly its size; cancelling leaves three files.
- **REC-010-S2**: Rows are ordered newest first in every test ordering.
- **REC-010-S3**: A readable recording gets a non-empty thumbnail; a second request is served from the cache.
- **REC-010-S4**: An unreadable file is listed as Incomplete with Delete only.
- **REC-010-S5**: Clear Caches leaves saved recordings untouched; Erase with "Saved recordings" removes them.
- **REC-010-S6**: The UI test (open Recordings with three seeded files, delete one with confirmation, the count drops to two) runs in under 30 s.

## Assumptions

- Recordings are at most 10 minutes (REC-003), so per-file reads stay short; per-row facts are read once per screen visit and cached by name and size.
- The library folder is part of the app container and of the device's own backup; it is not part of the FILE-005 library backup (large media the user can share instead).
- Device checks (Keep, play and share on D1) are a `{device}` task; simulator results are not evidence.
