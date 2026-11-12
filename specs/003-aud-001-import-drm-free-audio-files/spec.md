# Feature Specification: AUD-001 Import DRM-free audio files

**Feature Branch**: `feature/aud-001` (spec directory `003-aud-001-import-drm-free-audio-files`)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Implement AUD-001 (Import DRM-free audio files) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Choose supported audio in Files
and copy into a managed local library." Acceptance, verbatim: "Import a valid file, relaunch
offline, and play it without a security-scoped URL." Dependencies: none. Honor the repository
constitution."

Identifiers in this feature carry the roadmap ID so they never collide with features 001 and 002:
requirements are `AUD-001-R1…`, success criteria `AUD-001-S1…`, tasks `AUD-001-T01…`. Requirements
of feature 001 (`specs/001-ios-projectm-visualizer/spec.md`) and feature 002 stay in force unless a
line below amends one explicitly.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Import my own audio and watch it (Priority: P1)

A user who owns DRM-free audio files opens the source chooser, taps "Import Audio…", picks one or
more audio files in the system Files picker, and sees them appear in a "Your Audio" list. Tapping
a track starts In-App Playback with that track: it is audible through the current output, loops
until stopped, and the visualizer reacts to it. The source indicator reads "In-App Playback".

**Why this priority**: This is the roadmap row's observable behavior. Without it the app can only
play one bundled reference track, and every later audio feature (formats, queue, transport)
builds on the library created here.

**Independent Test**: Import a generated test tone from Files, tap it in the list, and observe
"In-App Playback" with "Active audio" and a moving visualization.

**Acceptance Scenarios**:

1. **Given** the source chooser, **When** the user taps "Import Audio…" and picks a valid audio
   file, **Then** the file is copied into the app's library and its title and duration appear
   under "Your Audio".
2. **Given** an imported track in the list, **When** the user taps it, **Then** the visualizer
   opens, the track plays audibly and loops, and the source indicator shows "In-App Playback".
3. **Given** the Files picker is open, **When** the user cancels, **Then** nothing changes and no
   message is shown.
4. **Given** the user picks several files at once, **When** the import finishes, **Then** every
   valid file is in the list and one message names each file that was not imported and why.
5. **Given** a track is playing, **When** the user taps Stop, **Then** playback stops within 1 s
   and the chooser returns, as for every other source (FR-007).

---

### User Story 2 - My library is still there offline, without the original (Priority: P1)

After importing, the user deletes or moves the original file (or it lived on a drive or cloud
folder that is no longer reachable), turns on Airplane Mode and relaunches the app. The track is
still listed and plays exactly as before.

**Why this priority**: This is the roadmap row's acceptance criterion. The copy in the library,
not the picked location, is the track.

**Independent Test**: Import a file, delete the original, relaunch with no network, and play the
track from the list.

**Acceptance Scenarios**:

1. **Given** an imported track, **When** the app is relaunched with no network, **Then** the track
   is listed with the same title and duration.
2. **Given** an imported track whose original file was deleted, **When** the user taps it,
   **Then** it plays; the app never asks for the original location again.
3. **Given** an import was interrupted (the app was killed mid-copy), **When** the app relaunches,
   **Then** the library lists only complete tracks and holds no leftover partial file.

---

### User Story 3 - Files that cannot be imported are refused clearly (Priority: P2)

The user picks something the app cannot use: a file that is not audio, a damaged file, a
copy-protected (DRM) purchase, a file that is too large, or audio with more than two channels.
The app refuses it, says why in plain words, and leaves the library exactly as it was.

**Why this priority**: Imported files are untrusted input (Constitution, Security). A refused
file must never crash the app, half-appear in the library, or be worked around.

**Independent Test**: Pick a text file renamed to `.wav`, an oversized file and a non-audio file;
each produces its own message and the list is unchanged.

**Acceptance Scenarios**:

1. **Given** a file that is not an audio type, **When** it is picked, **Then** the app shows
   "This file isn't a supported audio file." and adds nothing.
2. **Given** a damaged or undecodable audio file, **When** it is picked, **Then** the app shows
   "This audio file can't be read. It may be damaged." and adds nothing.
3. **Given** a DRM-protected file, **When** it is picked, **Then** the app shows "This file is
   copy-protected (DRM) and can't be imported." and adds nothing; no attempt is made to remove the
   protection.
4. **Given** a file larger than the limit, **When** it is picked, **Then** the app shows the size
   limit and adds nothing.
5. **Given** any refused or failed import, **When** it ends, **Then** no partial copy remains in
   the app's storage.
6. **Given** a file whose content is already in the library, **When** it is picked again,
   **Then** no second copy is stored and the app says the track is already in the library.

---

### User Story 4 - Remove a track I no longer want (Priority: P3)

The user swipes a track in "Your Audio" (or uses the VoiceOver delete action) to remove it. The
track leaves the list and its copy is deleted from the app's storage.

**Why this priority**: A library the user can only add to would grow without bound; removal is the
minimum needed to manage storage. Queueing, ordering and renaming are later features.

**Independent Test**: Import a track, remove it, relaunch; it is gone and its storage is freed.

**Acceptance Scenarios**:

1. **Given** an imported track that is not playing, **When** the user removes it, **Then** it
   disappears from the list, its copy is deleted, and it stays gone after a relaunch.

---

### Edge Cases

- The picked file is in a cloud folder and not downloaded: the system picker and file coordination
  provide it; if the system cannot, the import fails with "This file couldn't be opened." The app
  itself makes no network connection (FR-068).
- The device runs out of storage during the copy: the import fails with a storage message and the
  partial copy is removed.
- Two files with the same name but different content: both are imported; each keeps its own title.
- The same content under two names: the second pick is a duplicate (Story 3, scenario 6).
- A file with no extension or a misleading extension: the declared type is checked first, then the
  file must decode; a text file named `.wav` is refused as unreadable.
- An empty (zero-length) audio file: refused as unreadable.
- The library's record of tracks is damaged or was written by a newer app version: see
  AUD-001-R14 and AUD-001-R15.
- The stored copy of a listed track is missing (for example after a partial device restore): the
  track is dropped from the list at the next launch; nothing else is affected.
- A track is removed while it is playing: not possible in this feature, because the list is only
  reachable from the source chooser, where nothing is playing.
- An interruption (call, alarm) or a lost output route during playback of an imported track
  behaves exactly as for the reference track (FR-051); checked on devices in the final phase.

## Requirements *(mandatory)*

### Functional Requirements

**Import**

- **AUD-001-R1**: The source chooser MUST offer an "Import Audio…" action that opens the system
  Files picker limited to audio files, allowing one or several files to be picked. Import starts
  only from this user action.
- **AUD-001-R2**: Each picked file that passes validation MUST be copied into a library managed by
  the app, in storage that is private to the app, persists across launches and app updates, and is
  not purgeable by the system when storage runs low.
- **AUD-001-R3**: After a successful import the app MUST NOT need the picked location again: it
  MUST NOT store the picked location, a bookmark to it, or any security-scoped reference, and
  listing and playing the track MUST work when the original is deleted or unreachable.
- **AUD-001-R4**: Imported files MUST be treated as untrusted input. Before a file enters the
  library the app MUST verify that (a) its declared type is audio, (b) its size is at most
  500 MB, enforced on the bytes actually copied, (c) it is not DRM-protected, (d) the system
  decoder can open it and read audio from it, and (e) it has one or two channels, a positive
  sample rate and at least one frame.
- **AUD-001-R5**: A file that fails any check, or an import that fails for any other reason
  (unreadable source, no storage space, interrupted copy), MUST leave the library unchanged: no
  list entry and no partial or temporary file once the import ends or, after a crash, once the app
  next launches.
- **AUD-001-R6**: Every failed import MUST produce a clear, user-visible message naming the file
  and the reason. The reasons are: not a supported audio file; unreadable or damaged; DRM-protected;
  too large (stating the limit); unsupported channel count; not enough storage; file could not be
  opened; library unavailable. The exact strings are in `contracts/ui-strings.md`.
- **AUD-001-R7**: The app MUST NOT attempt to decrypt, strip, or otherwise circumvent DRM or any
  content protection. A protected file is refused (Constitution I, FR-003).
- **AUD-001-R8**: Importing content that is already in the library (byte-identical) MUST NOT store
  a second copy; the existing track is kept and the user is told the track is already in the
  library.
- **AUD-001-R9**: While files are being imported the chooser MUST show that an import is in
  progress, and the import MUST NOT block the interface.

**Library**

- **AUD-001-R10**: The chooser MUST list imported tracks under "Your Audio", most recently
  imported first, each with its title (the picked file's name without extension) and duration.
- **AUD-001-R11**: The library MUST record, for each track: a stable identifier, title, original
  file name, content hash, stored file name, size, duration, sample rate, channel count and import
  date. It MUST NOT record absolute paths, the picked location, or any playback history.
- **AUD-001-R12**: The library's record MUST carry a format version and MUST be written atomically,
  so a crash or power loss during a write leaves either the old or the new record, never a
  truncated one.
- **AUD-001-R13**: Users MUST be able to remove an imported track; removal deletes its stored copy
  and its record entry.
- **AUD-001-R14**: If the library's record is unreadable, the app MUST keep the damaged record
  aside (not delete it), rebuild the list from the stored copies that still decode, and continue;
  rebuilt tracks may lose their original title.
- **AUD-001-R15**: If the library's record was written by a newer format version than this app
  understands, the app MUST leave the record and the stored copies untouched, show the library as
  unavailable with a message, and refuse imports and removals until an app version that
  understands it runs.
- **AUD-001-R16**: At launch the library MUST delete leftover temporary files from interrupted
  imports and stored copies that no record entry refers to, and MUST drop record entries whose
  stored copy is missing.

**Playback**

- **AUD-001-R17**: Tapping an imported track MUST start the existing In-App Playback source with
  that track: audible through the current output route at the system media volume, looping until
  stopped, never opening an input (FR-006, FR-069), with the same stop, pause, interruption and
  route-loss behavior as the reference track (FR-007, FR-050, FR-051).
- **AUD-001-R18**: An imported track MUST be labeled "In-App Playback" wherever the active source
  is shown (Constitution IV, FR-013). The app MUST NOT label it as System/App Capture or
  Microphone, and audio states follow FR-010 unchanged.
- **AUD-001-R19**: If an imported track cannot be played (its copy is missing or no longer
  decodes), the app MUST report "In-App Playback failed" (FR-006, FR-015) and MUST NOT fall back
  to another track silently.
- **AUD-001-R20**: Playback of an imported track MUST NOT load the whole track into memory, and
  the real-time audio path MUST stay free of allocation, locks with unbounded wait, and file I/O
  (Constitution VII).
- **AUD-001-R21**: The built-in reference track MUST remain available and unchanged as the
  "In-App Playback" row of the chooser.

**Privacy, compliance and accessibility**

- **AUD-001-R22**: This feature amends FR-065: on-device persistence additionally includes the
  audio files the user explicitly imports and the library record of AUD-001-R11. Everything else
  in FR-065 stands: no captured, microphone or system audio is ever stored, and no listening or
  source-app history is kept.
- **AUD-001-R23**: The feature MUST make no network connection and add no networking code, no
  entitlement, no background mode and no new permission prompt (FR-068, Constitution I). Imported
  audio and the library record never leave the device through this feature; the diagnostics export
  (FR-021) MUST NOT include track titles, file names or audio.
- **AUD-001-R24**: Every new control and row MUST have an accessible label, text MUST scale with
  the system text size, removal MUST be available to VoiceOver users, and the import result MUST be
  announced to screen-reader users (FR-070).

### Key Entities

- **Imported track**: one audio file the user imported. Identifier, title, original file name,
  content hash, stored file name, size, duration, sample rate, channel count, import date.
- **Audio library**: the app-managed collection of imported tracks: the stored copies plus one
  versioned record listing them.
- **Import outcome**: per picked file, either imported, already in the library, or refused with
  one reason.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-001-S1**: A valid audio file picked in Files appears in "Your Audio" and can be played with
  one further tap; a 10 MB file is listed within 2 seconds of being picked on the reference phone.
- **AUD-001-S2**: After importing, deleting the original and relaunching with no network, 100% of
  imported tracks are listed and play.
- **AUD-001-S3**: For every refusal reason in AUD-001-R6, the picked file produces its message and
  the app's storage holds zero additional files afterwards.
- **AUD-001-S4**: Importing the same content twice stores it once.
- **AUD-001-S5**: A damaged library record never prevents the app from launching or from playing
  the reference track, and tracks whose copies are intact remain playable.
- **AUD-001-S6**: While an imported track plays, the source indicator reads "In-App Playback" and
  the audio state reaches "Active audio" for non-silent content.
- **AUD-001-S7**: Playing a 60-minute imported track does not raise the app's memory use by more
  than 50 MB over playing the reference track (measured on a device in the final phase).

## Assumptions

- "Supported audio" in this feature means: a file whose type the system identifies as audio and
  that the system's audio file decoder can open. AUD-002 adds the per-format guarantee (MP3, AAC,
  M4A, WAV, AIFF fixtures) and format-specific error wording on top of this library.
- One track plays at a time and loops, like the reference track. Queue, repeat modes, shuffle and
  transport (seek, next, previous) are AUD-003 to AUD-006 and are out of scope; the library record
  is versioned so they can extend it.
- Titles come from file names. Reading embedded tags (artist, album, artwork), renaming and
  sorting are out of scope.
- No limit on the number of tracks; device storage is the limit and the out-of-storage error
  covers it.
- The library is included in the user's normal device backup, like other app data; nothing is done
  to exclude it.
- Import and removal are offered in the `projectM-iOS` app only. CaptureLab (the tester harness)
  keeps the reference track only.
- The user is responsible for having the right to use the files they import; the app plays them
  locally and never redistributes them.
- English-only strings, as in feature 001.
- Physical-device checks (output routes, interruptions, memory on a long track, a real DRM
  purchase) happen in the roadmap's final device phase and are tagged `{device}` in tasks.
