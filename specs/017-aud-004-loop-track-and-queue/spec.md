# Feature Specification: AUD-004 Loop track and queue

**Feature Branch**: `feature/aud-004` (spec directory `017-aud-004-loop-track-and-queue`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement AUD-004 (Loop track and queue) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Offer off, one-track and
all-tracks repeat modes." Acceptance, verbatim: "End-of-track behavior matches each repeat mode under
deterministic clock tests." Dependencies: AUD-003 (integrated). Honor the repository constitution."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `AUD-004-R1…`, success criteria `AUD-004-S1…`, tasks `AUD-004-T01…`. Requirements
of feature 001 (`specs/001-ios-projectm-visualizer/spec.md`), AUD-006
(`specs/007-aud-006-seekable-transport/spec.md`), AUD-014
(`specs/009-aud-014-audio-session-interruption-recovery/spec.md`), AUD-016
(`specs/011-aud-016-reference-tone-suite/spec.md`), QA-007
(`specs/013-qa-007-audio-source-contract-suite/spec.md`) and AUD-003
(`specs/015-aud-003-audio-library-queue/spec.md`) stay in force unless a line below amends one
explicitly. Amended here: AUD-006-R17 and AUD-003-R9 for the "Off" and "One Track" modes only (with
"All Tracks", the default, both apply unchanged), and AUD-003-R13 (the queue record may also hold the
repeat mode).

## Baseline: what exists today (audit of 2026-11-13)

| Capability | Today |
|---|---|
| End of an imported track | The next track in the queue, wrapping from the last to the first; a queue of one repeats without a gap (AUD-006-R17, AUD-003; owner ruling 2026-11-12) |
| Repeat one track while others are queued | No |
| Stop after the last queued track | No: playback never ends by itself while anything is queued |
| Choose a repeat mode | No control; the roadmap row says "Repeat modes stay with AUD-004" (ADR-0008) |
| The playing track removed from the queue | It plays to its end, then the track at its former place follows, wrapping; an empty queue stops at the end of the track (AUD-003-R9) |
| Live change of repetition | The queue's change notification re-evaluates whether the current track repeats and applies it at once, keeping the position, without a cut (AUD-003-R8) |
| Reference track, test signals | An order of one; they repeat (AUD-006-R14, AUD-016-R17) |

Today's behavior is what this feature calls "All Tracks". The transport already asks a replaceable
play order what follows a track; this feature lets the queue answer by repeat mode, gives the user a
control for it, and stores the choice with the queue.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stop after the last track (Priority: P1)

A user plays an album-like set of imported tracks and wants playback to stop when the last one ends,
instead of starting over. They set Repeat to "Off".

**Why this priority**: The only way to make playback end by itself; the most requested difference
from today's endless wrap.

**Independent Test**: With three queued tracks A, B, C and Repeat Off, play A to its end: B follows,
then C; at the end of C playback stops, and Play starts the queue again from A.

**Acceptance Scenarios**:

1. **Given** Repeat Off and the queue A, B, C, **When** A plays to its end, **Then** B starts at its
   first frame, with nothing of A cut off.
2. **Given** Repeat Off and C (the last queued track) playing, **When** C reaches its end, **Then**
   playback stops: the state is "Stopped", the current track becomes A (the first queued track) at
   0:00, and nothing more is heard.
3. **Given** playback stopped after the end of the queue, **When** the user taps Play, **Then** A
   plays from 0:00.

---

### User Story 2 - Repeat one track (Priority: P1)

A user wants the visualizer to stay on one song. They set Repeat to "One Track"; the playing track
repeats without a gap while the rest of the queue waits.

**Why this priority**: Equal to Story 1 in the roadmap row; long single-track visual sessions are a
core use of a visualizer.

**Independent Test**: With A, B, C queued and Repeat One Track, A reaches its end and starts again
at its first frame without a gap; B never plays until the user taps Next.

**Acceptance Scenarios**:

1. **Given** Repeat One Track and A playing, **When** A reaches its end, **Then** A plays again from
   its first frame with no gap and no repeated or missing frames.
2. **Given** Repeat One Track, **When** the user taps Next track, **Then** B starts and then repeats
   at its end; Repeat stays One Track.
3. **Given** Repeat One Track and A playing at 1:05, **When** the user switches to All Tracks,
   **Then** A continues at 1:05 without a cut and B follows at A's end.

---

### User Story 3 - Repeat the whole queue (Priority: P1)

"All Tracks" keeps today's behavior: at the end of the last queued track the first starts again. It
is the default, so nothing changes for a user who never touches the control.

**Why this priority**: Preserves the owner ruling of 2026-11-12 and existing behavior.

**Independent Test**: With A, B, C and the default mode, C's end is followed by A.

**Acceptance Scenarios**:

1. **Given** a fresh install or a queue stored before this feature, **Then** the mode is All Tracks.
2. **Given** All Tracks and C playing, **When** C reaches its end, **Then** A starts at its first
   frame without a cut.

---

### User Story 4 - Choose the mode, accessibly, and keep it (Priority: P2)

The user changes the mode from a Repeat button in the transport while an imported track plays (each
tap moves to the next mode) or from a Repeat section in the queue screen, and the choice survives a
relaunch. VoiceOver reads the control as "Repeat" with its mode as the value; it works at every text
size.

**Why this priority**: The control makes the modes reachable; persistence keeps a choice the user
made deliberately.

**Independent Test**: Set each mode in turn, relaunch after each, and read the same mode back.

**Acceptance Scenarios**:

1. **Given** an imported track plays, **When** the user taps Repeat, **Then** the mode moves Off →
   All Tracks → One Track → Off, the button's value says the new mode, and the playing track's
   position does not change.
2. **Given** the queue screen, **When** the user selects "Off", "One Track" or "All Tracks", **Then**
   that row is marked selected and the transport's Repeat value matches.
3. **Given** a mode was chosen, **When** the app is relaunched, **Then** the same mode is shown and
   applies.
4. **Given** the reference track or a test signal plays, **Then** no Repeat control is shown and the
   track repeats as before.

### Edge Cases

- One queued track: Off plays it once and stops at 0:00 of the same track; One Track and All Tracks
  repeat it without a gap.
- The playing track removed from the queue: All Tracks follows AUD-003-R9 unchanged. One Track: the
  removed track no longer repeats; it plays to its end and the track at its former place follows
  (wrapping) and then repeats. Off: it plays to its end and the track at its former place follows;
  when that place is past the end of the queue, the end of the queue applies (stop, first queued
  track cued at 0:00). With an empty queue every mode stops at the end of the track, as today.
- The mode changes while paused, stopped or during an interruption: only what happens at the end of
  the track changes; the state, the position and the interruption's automatic resume stay as they
  were (the change is not a transport command).
- The mode changes on the last queued track from All Tracks to Off a moment before its end: the end
  that follows obeys Off.
- Paused at the very end of the last track (a seek to the end) with Off, then Play: the queue starts
  again at the first track (the same as Play after the end of the queue).
- The stored queue record was written by a newer app: the mode can be changed for this launch but is
  not stored, like every queue edit (AUD-003-R14); the mode starts as All Tracks.
- A stored mode the app does not know (written by a later app at the same record version): All Tracks.
- Next track and Previous track wrap in every mode (AUD-006-R15, R16 unchanged, including the
  3-second Previous rule); the mode only decides what happens when a track plays to its end.

## Requirements *(mandatory)*

### Functional Requirements

- **AUD-004-R1**: The app MUST offer three repeat modes for imported audio played from the queue:
  "Off", "One Track" and "All Tracks". The mode belongs to the queue (one per device) and applies to
  whichever queued track plays.
- **AUD-004-R2**: The default mode, for a fresh install and for a queue record stored before this
  feature, MUST be All Tracks, which behaves exactly as AUD-006-R17 and AUD-003 do today.
- **AUD-004-R3** (All Tracks): at the end of a track the next queued track MUST play from its first
  frame; after the last queued track the first follows; a queue of one repeats without a gap.
- **AUD-004-R4** (One Track): a queued current track MUST repeat from its first frame without a gap
  at its end, indefinitely; no other track plays until the user moves playback.
- **AUD-004-R5** (Off): at the end of a track that is not the last queued track, the next queued track
  MUST play from its first frame. At the end of the last queued track playback MUST stop: the
  transport state becomes Stopped (as after Stop playback, AUD-006-R5; the session and the visualizer
  stay), the current track becomes the first queued track at 0:00, and no further audio plays.
- **AUD-004-R6**: Play while stopped after the end of the queue, and Play while paused at the very end
  of the last track with Off, MUST play the first queued track from 0:00.
- **AUD-004-R7**: Next track and Previous track MUST keep AUD-006's rules (wrapping, the 3-second
  Previous rule) in every mode; in One Track the newly selected track then repeats.
- **AUD-004-R8**: A track that plays to its end and is followed by another MUST hand over without a
  cut: every frame of the ending track is delivered before the first frame of the next, as AUD-006
  does today.
- **AUD-004-R9**: Changing the mode MUST NOT move the position, cut, restart or pause the playing
  track, and MUST NOT count as a transport command or as a user transport change for interruption
  recovery (AUD-014-R2; like AUD-003-R12). Whether the current track repeats MUST follow the new mode
  at once (the live update of AUD-003-R8).
- **AUD-004-R10** (removal): with the playing track removed from the queue, All Tracks MUST follow
  AUD-003-R9 unchanged; One Track MUST treat the removed track as not repeating (it plays to its end,
  then the track at its former place, wrapping, which then repeats); Off MUST follow AUD-003-R9 but
  without wrapping: when the former place is past the end of the queue, R5's end of queue applies. An
  empty queue MUST stop at the end of the track in every mode.
- **AUD-004-R11**: The reference track and the test-signal tracks MUST keep repeating as an order of
  one (AUD-006-R14, AUD-016-R17); the repeat mode does not apply to them and its control is not shown
  for them.
- **AUD-004-R12**: The transport MUST show a Repeat button while an imported track is the current
  item. Each tap MUST move the mode Off → All Tracks → One Track → Off. Its accessibility label MUST be
  "Repeat" and its value the mode's name; a change MUST be announced to VoiceOver. Its icon MUST
  distinguish the three modes, and it MUST stay usable at every Dynamic Type size.
- **AUD-004-R13**: The queue screen MUST show a "Repeat" section listing the three modes as
  selectable rows (the current one marked selected for VoiceOver too), reachable from the chooser and
  from the transport.
- **AUD-004-R14**: The mode MUST be stored with the queue (`queue.json`) whenever it changes, with the
  same atomic write, failure and newer-version rules as every queue edit (AUD-003-R13, R14). The
  record change MUST be additive: a record without a mode reads as All Tracks; an app that predates
  this feature MUST still read the record (it ignores the mode); an unknown mode reads as All Tracks.
- **AUD-004-R15**: Nothing new runs on the real-time audio path: no allocation, lock, file access or
  logging is added to any audio callback (Constitution VII). The mode is decided on the main actor.
- **AUD-004-R16**: Labels stay truthful (Constitution IV): the source remains "In-App Playback" in
  every mode, and a stopped end of queue shows "Stopped", never "Receiving audio" as playing.
- **AUD-004-R17**: Behavior with real audio routes and interruptions on hardware MUST be checked on a
  physical device in the device phase (`{device}`); simulator and offline results are not device
  evidence.

### Key Entities

- **Repeat mode**: Off, One Track or All Tracks; belongs to the queue.
- **Queue record** (`queue.json`, AUD-003): format version 1, queued identifiers, current identifier,
  and now an optional repeat mode (absent means All Tracks).
- **End-of-track step**: what the play order answers when a track ends: play an item (the same item
  means repeat), or stop (optionally cueing an item at 0:00).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-004-S1** (roadmap acceptance): With three generated tracks played through the production
  pipeline under a deterministic (offline, injected) clock, for each mode the end of the current track
  and the end of the queue behave exactly as R3 to R6 say in 100% of runs: every frame of each track
  reaches the analysis in order, the next item starts at its first frame, One Track wraps from the
  last frame to the first with no frame missing or repeated, and Off delivers nothing after the last
  frame of the last track and leaves the transport Stopped at the first track's 0:00.
- **AUD-004-S2**: Switching the mode in the middle of a track keeps the position to within one sample
  and delivers the track's frames consecutively across the switch, and the following end of track obeys
  the new mode, in 100% of runs.
- **AUD-004-S3**: Two runs of the same scenario deliver identical frame sequences.
- **AUD-004-S4**: A mode set from the UI is shown again after a relaunch in 100% of UI test runs, for
  each of the three modes.
- **AUD-004-S5**: The Repeat control and the queue screen's Repeat rows are operable with VoiceOver
  and fully readable at the largest accessibility text size.
- **AUD-004-S6**: The QA-007 contract suite and every AUD-006, AUD-014, AUD-016 and AUD-003 test still
  pass.

## Assumptions

- One mode for the one queue; no per-track repeat settings.
- Shuffle with history (AUD-005) is a separate feature that will build on these modes; nothing of it
  is implemented here.
- The playback position is still not stored (AUD-003); a relaunch restores the mode and the queue,
  not playback.
- Interruption behavior (AUD-014) is unchanged; at a stopped end of queue there is nothing to resume.
