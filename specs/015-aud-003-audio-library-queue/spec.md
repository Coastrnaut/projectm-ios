# Feature Specification: AUD-003 Audio library queue

**Feature Branch**: `feature/aud-003` (spec directory `015-aud-003-audio-library-queue`)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Implement AUD-003 (Audio library queue) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Queue locally imported tracks and
reorder them while playback continues." Acceptance, verbatim: "Reordering three tracks changes
next-track order and persists across relaunch." Dependencies: AUD-001 (integrated); replaces
AUD-006's ListPlayOrder for imported audio. Honor the repository constitution."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `AUD-003-R1…`, success criteria `AUD-003-S1…`, tasks `AUD-003-T01…`. Requirements
of feature 001 (`specs/001-ios-projectm-visualizer/spec.md`), AUD-001
(`specs/003-aud-001-import-drm-free-audio-files/spec.md`), AUD-002
(`specs/006-aud-002-support-common-audio-containers/spec.md`), AUD-006
(`specs/007-aud-006-seekable-transport/spec.md`), AUD-014
(`specs/009-aud-014-audio-session-interruption-recovery/spec.md`), AUD-016
(`specs/011-aud-016-reference-tone-suite/spec.md`) and QA-007
(`specs/013-qa-007-audio-source-contract-suite/spec.md`) stay in force unless a line below amends one
explicitly. Amended here: AUD-006-R14 (the play order of imported audio becomes the queue) and the
part of AUD-006-R30 that says no order is written to disk (the queue is stored; nothing else of the
transport is).

## Clarifications

### Session 2026-11-12

Answered by Claude under the owner's standing approval (CLAUDE.md owner rule 4: best judgement on
all choices, no human interaction); each answer is the recommended, conservative, local-first
option using public APIs only.

- Q: How does the queue relate to the "Your Audio" library list? → A: An explicit queue separate from the library, which starts as the library list order (newest first) and diverges once edited. New imports join it at the top, matching the list; removing from the queue never deletes; deleting from the library removes from the queue; a track is in the queue at most once. Rejected: making the library list itself reorderable (removing a track from the order would then delete the file), and an empty-by-default queue (would silently change AUD-006 behavior for existing users) (AUD-003-R1 to R6).
- Q: What happens when the playing track is removed from the queue? → A: It plays to its end, without interruption; then the track now at its former place in the queue plays (wrapping to the first when the place is past the end). With an empty queue playback stops at the end of the track. Next and Previous track use the same place. Rejected: skipping to the next track at once (an interruption the roadmap forbids) and stopping at once (AUD-003-R9).
- Q: Where and how is the queue stored? → A: In a separate versioned file, `queue.json`, next to AUD-001's `index.json` in the app's private library folder, written atomically; it holds only track identifiers and the current identifier. AUD-001's index keeps version 1 untouched, so no library migration is needed and a queue problem can never damage the library. Damaged: kept aside as `queue.damaged.json`, the queue restarts from the library order. Newer version: left untouched, this launch uses the library order and does not store edits (AUD-003-R13, R14, R16).
- Q: Does a queue edit during an interruption cancel the automatic resume, as a user transport change does (AUD-014-R2)? → A: No. A queue edit never moves playback, so it is not a transport change; resume follows the interruption policy exactly as without the edit (AUD-003-R12).
- Q: How is the queue reached while the visualizer plays, given the chooser is not on screen then? → A: A "Queue" button in the transport opens the queue as a sheet over the visualizer; the same screen opens from a "Queue" row in "Your Audio" in the chooser, where it also offers "Play Queue". In the sheet, tracks not in the queue are listed below it with "Add to Queue" and "Play Next" (AUD-003-R10).

## Baseline: what exists today (audit of 2026-11-12)

| Capability | Today |
|---|---|
| Play order of imported tracks | The "Your Audio" list as shown when playback started (newest import first), fixed for the session (AUD-006-R14) |
| Choose which tracks play, or in which order | No |
| Change the order while playing | No: the chooser, where the list is, is not reachable while the visualizer plays |
| Remember an order across launches | No: the transport stores nothing (AUD-006-R30) |
| End of a track | The next track in the order, wrapping; one track repeats without a gap (AUD-006-R17, owner ruling 2026-11-12) |
| Reference track, test signals | An order of one; they repeat (AUD-006-R14, AUD-016-R17) |

The transport already asks a replaceable "play order" what comes after and before the current
track (AUD-006-R14). This feature puts a user-editable, stored queue behind that interface for
imported audio and changes nothing for the reference track, the test signals, Microphone or
System/App Capture.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reorder what plays next while the music keeps playing (Priority: P1)

While an imported track plays in the visualizer, the user opens the queue from the transport,
drags (or, with VoiceOver, moves) a track to another place, and closes it. The track that is
playing is not interrupted: no gap, no restart, the position keeps advancing. When it ends, and
when the user taps Next track, playback follows the new order.

**Why this priority**: It is the roadmap's observable behavior and the first half of its acceptance.

**Independent Test**: Import three tracks, start the first, reorder the other two in the queue
while it plays, let it end (or tap Next track) and check which track plays.

**Acceptance Scenarios**:

1. **Given** the queue is A, B, C and A is playing, **When** the user moves C above B, **Then** A
   keeps playing from where it was without a gap, and the track after A is C, then B.
2. **Given** the same queue, **When** the user taps Next track after the reorder, **Then** C plays
   from 0:00; Previous track (within 3 seconds) goes back to A.
3. **Given** playback is paused, **When** the user reorders the queue, **Then** playback stays
   paused at the same position.

---

### User Story 2 - The order survives a relaunch (Priority: P1)

The user reorders the queue, leaves the app (or it is ended), and opens it again. The queue shows
the same order, the track that was last playing is marked, and nothing plays until the user
starts it.

**Why this priority**: The second half of the roadmap acceptance.

**Independent Test**: Reorder three tracks, terminate and relaunch the app, open the queue.

**Acceptance Scenarios**:

1. **Given** the user reordered the queue to C, A, B, **When** the app is relaunched, **Then** the
   queue lists C, A, B and the last played track is marked as the current track.
2. **Given** a relaunch, **When** the chooser appears, **Then** no audio plays until the user starts
   a track or the queue.
3. **Given** a stored queue, **When** the user taps "Play Queue", **Then** playback starts with the
   marked current track at 0:00 (or the first track when none is marked) and continues in queue order.

---

### User Story 3 - Choose what is in the queue (Priority: P2)

From the chooser's "Your Audio" list and from the queue screen, the user adds a track to play
next or at the end, removes tracks from the queue without deleting them from the library, and
clears the queue. Newly imported tracks join the queue automatically.

**Why this priority**: Makes the queue a real queue rather than only a re-sorted library; also
needed while playing, when the library list is not reachable.

**Independent Test**: With five imported tracks, remove two from the queue, add one back to play
next, and check the order Next track follows.

**Acceptance Scenarios**:

1. **Given** a track is not in the queue, **When** the user chooses "Add to Queue", **Then** it is
   placed at the end; with "Play Next" it is placed right after the current track.
2. **Given** a track is already in the queue, **When** the user chooses "Play Next" for it,
   **Then** it moves to right after the current track (a track is never in the queue twice).
3. **Given** the user removes a track from the queue, **Then** it stays in "Your Audio" and its
   file is untouched; deleting a track from the library removes it from the queue too.
4. **Given** the queue is cleared while a track plays, **Then** that track plays to its end and
   playback then stops at the end (nothing is queued).

---

### User Story 4 - Accessible queue editing (Priority: P2)

VoiceOver users reorder with "Move Up" and "Move Down" actions on each queue row and remove with
"Remove from Queue"; every control has a label; the queue reads well at the largest text sizes.

**Why this priority**: Constitution and feature 001 FR-070 require it.

**Independent Test**: With VoiceOver actions (or the UI test equivalents) move a row and check the
new order and the announced position.

**Acceptance Scenarios**:

1. **Given** VoiceOver is on, **When** the user picks "Move Down" on the first row, **Then** it
   becomes the second row and its label states its new position ("2 of 3").
2. **Given** the largest accessibility text size, **Then** titles wrap to two lines and no control
   is cut off.

### Edge Cases

- The playing track is removed from the queue: it keeps playing to its end, then the track that
  took its place in the queue plays (AUD-003-R9).
- The queue holds only the playing track and the user adds a second one: the playing track no
  longer repeats; it plays to its end and the added track follows, without a cut and without the
  position moving (AUD-003-R8).
- The user removes every other track while one plays: that track repeats without a gap again
  (AUD-003-R8).
- A stored queue names tracks that are no longer in the library: they are dropped silently.
- The stored queue file is unreadable: it is kept aside and the queue is rebuilt from the library
  order; the library itself is untouched.
- The stored queue file was written by a newer app version: it is not changed; this launch uses
  the library order and does not store edits.
- The library cannot be used (AUD-001-R15): the queue is not changed and its controls are not offered.
- A queue edit during an interruption (call, Siri): playback stays on hold; the edit does not
  cancel an automatic resume, because it does not move playback (AUD-003-R12).
- The next track in the queue cannot be opened: the session ends with "In-App Playback failed",
  as today (AUD-006-R19); no other track is substituted.
- An empty library: the queue screen shows that nothing is queued; "Play Queue" is not offered.
- Reference track and test signals: unchanged, each alone in its order; the queue is not shown.

## Requirements *(mandatory)*

### Functional Requirements

**The queue**

- **AUD-003-R1**: The app MUST keep one queue: an ordered list of imported tracks, each at most
  once. It is the play order of imported audio: Next track, Previous track and the end of a track
  follow it (AUD-006-R15 to R17 unchanged, with "the order" meaning the queue as it is at that moment).
- **AUD-003-R2**: When no queue has been stored yet, the queue MUST be every imported track in the
  "Your Audio" list order (newest import first), so behavior is unchanged until the user edits it.
- **AUD-003-R3**: A newly imported track MUST be added to the queue at the top, in the same order
  "Your Audio" shows new imports. A duplicate import (AUD-001-R8) changes nothing.
- **AUD-003-R4**: Starting an imported track from "Your Audio" MUST play it with the queue as the
  order. A track that is not in the queue is first added at the end of it.
- **AUD-003-R5**: The user MUST be able to: add a track to play next (right after the current
  track, or at the top when there is none) or at the end; move a queued track to any place (drag in
  Edit mode, Move Up, Move Down); remove a track from the queue; clear the queue (with
  confirmation). Adding a queued track again moves it.
- **AUD-003-R6**: Removing a track from the queue or clearing it MUST NOT delete it from the
  library. Deleting a track from the library (AUD-001-R13) MUST remove it from the queue.

**While playback continues**

- **AUD-003-R7**: Editing the queue MUST NOT stop, restart, pause, seek or cut the playing track:
  no audio is discarded, the position keeps advancing from where it was, and the transport state
  (playing, paused, stopped) stays as it is.
- **AUD-003-R8**: When an edit changes whether the playing track is alone in the order, its
  repetition MUST follow at once and keep its position: alone, it repeats without a gap
  (AUD-006-R17); no longer alone, it plays to its end and the next queued track follows.
- **AUD-003-R9**: When the playing track is removed from the queue (or the queue is cleared), it
  MUST keep playing to its end. Then the track now at its former place plays (the first track if
  that place is past the end); with an empty queue playback stops at the end of the track, as for
  an order that reports nothing follows (AUD-006-R17). Next and Previous track use the same place.
- **AUD-003-R10**: The queue MUST be reachable while In-App Playback plays an imported track (from
  the transport) and from the chooser's "Your Audio" section. It is not offered for the reference
  track, test signals, Microphone or System/App Capture.
- **AUD-003-R11**: The queue screen MUST mark the current track ("Now Playing" while it plays,
  "Current" otherwise).
- **AUD-003-R12**: A queue edit MUST NOT count as a user change of the transport for interruption
  recovery (AUD-014): it does not cancel an automatic resume and does not end a user stop.

**Persistence**

- **AUD-003-R13**: The queue order and the current track MUST be stored on the device, in the app's
  private library storage, and survive relaunch. Only track identifiers are stored: no titles,
  paths, positions or audio. The record has a format version and is replaced atomically, so a
  crash leaves either the old or the new queue.
- **AUD-003-R14**: Loading MUST tolerate damage: identifiers of tracks no longer in the library are
  dropped; an unreadable record is kept aside and the queue starts from the library order; a record
  of a newer version is left untouched and edits are not stored during that launch.
- **AUD-003-R15**: Nothing MUST play on relaunch until the user starts it. "Play Queue" starts the
  stored current track (the first queued track when none) at 0:00.
- **AUD-003-R16**: The stored library record (AUD-001's index) MUST NOT change format.

**Accessibility, privacy and platform**

- **AUD-003-R17**: Every queue control MUST have a VoiceOver label; queue rows MUST offer "Move
  Up", "Move Down" and "Remove from Queue" as VoiceOver actions and state their position ("2 of 3");
  library rows MUST offer "Play Next" and "Add to Queue". Text MUST follow Dynamic Type.
- **AUD-003-R18**: The feature MUST use only public platform APIs, no network, no new permission,
  entitlement, background mode or dependency. Audio work on the real-time path MUST NOT allocate
  or lock (Constitution VII).
- **AUD-003-R19**: The design MUST leave room for repeat modes (AUD-004) and shuffle with history
  (AUD-005) to build on the queue without changing its stored order; neither is implemented here.

### Key Entities

- **Queue**: the ordered list of queued imported tracks (by identifier, each once) plus the current
  track; derived views add titles and lengths from the library.
- **Queue record**: the stored form: format version, queued identifiers in order, current
  identifier (optional).
- **Imported track**: AUD-001's library entry; the queue refers to it by identifier only.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-003-S1** (roadmap acceptance): With three imported tracks playing in order A, B, C,
  moving C above B while A plays makes the track after A be C in 100% of runs, with A's audio
  continuing without a gap or a position change; after a simulated relaunch the queue is A, C, B with
  the current track preserved.
- **AUD-003-S2**: A relaunch of the app shows the reordered queue of three tracks in the same order
  in 100% of UI test runs, with nothing playing.
- **AUD-003-S3**: Every queue edit (add, move, remove, clear) is stored before the edit returns
  control, and a damaged, missing or newer-version record never loses the library.
- **AUD-003-S4**: All queue rows and controls are reachable and operable with VoiceOver actions
  and remain fully readable at the largest accessibility text size.
- **AUD-003-S5**: The QA-007 audio source contract suite and all AUD-006, AUD-014 and AUD-016
  tests still pass unchanged.

## Assumptions

- One queue per device; no named playlists (not in the roadmap).
- The queue holds imported tracks only; the reference track and test signals keep their own order
  of one.
- The playback position is not stored; "Play Queue" starts at 0:00.
- Behavior with real audio routes and interruptions on hardware is confirmed in the final device
  phase (`{device}`), not by simulator runs.
