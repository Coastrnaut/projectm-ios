# Feature Specification: AUD-005 Shuffle with history

**Feature Branch**: `feature/aud-005` (spec directory `023-aud-005-shuffle-with-history`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement AUD-005 (Shuffle with history) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Shuffle without immediately
repeating the current track and retain navigation history." Acceptance, verbatim: "Next and Previous
follow a reproducible seeded shuffle sequence." Dependencies: AUD-003 (integrated), AUD-004 repeat
modes (integrated). Honor the repository constitution and owner rule 7."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `AUD-005-R1…`, success criteria `AUD-005-S1…`, tasks `AUD-005-T01…`. Requirements of
feature 001 (`specs/001-ios-projectm-visualizer/spec.md`), AUD-006
(`specs/007-aud-006-seekable-transport/spec.md`), AUD-014
(`specs/009-aud-014-audio-session-interruption-recovery/spec.md`), AUD-003
(`specs/015-aud-003-audio-library-queue/spec.md`) and AUD-004
(`specs/017-aud-004-loop-track-and-queue/spec.md`) stay in force unless a line below amends one
explicitly. Amended here, while Shuffle is on only: AUD-006-R15 and R16 (Next and Previous follow the
shuffle order and the play history instead of the queue order; the 3-second Previous rule stays),
AUD-004-R5 (Off stops after a full shuffle cycle instead of after the last queued track) and
AUD-003-R13 (the queue record may also hold the shuffle state). With Shuffle off, the default,
nothing changes.

## Baseline: what exists today (audit of 2026-11-13)

| Capability | Today |
|---|---|
| Play order of imported audio | The queue order (AUD-003); Next and Previous wrap through it (AUD-006-R15, R16) |
| Shuffle | No: `PlayQueue` notes that AUD-005 "can be added on top of `ids` the same way" (AUD-003-R19) |
| History of played tracks | No: Previous selects the track before the current one in queue order |
| Repeat modes | Off, One Track, All Tracks; they decide only the end of a track (AUD-004) |
| Stored queue | `queue.json` version 1 with optional `repeatMode` (AUD-004-R14) |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Shuffle the queue (Priority: P1)

A user with many imported tracks wants them in a random order without rearranging the queue. They
turn Shuffle on; Next and the end of each track now move through a shuffled order of the queued
tracks, and the playing track is never chosen again right after itself.

**Why this priority**: The roadmap row's core behavior.

**Independent Test**: With five queued tracks and a fixed seed, turn Shuffle on while A plays; Next
four times visits the other four tracks once each in the seed's order, never A.

**Acceptance Scenarios**:

1. **Given** Shuffle on with a fixed seed, **When** the user taps Next repeatedly, **Then** the
   tracks follow the same sequence every time that seed is used, each queued track plays once per
   cycle, and the track just played never follows itself.
2. **Given** a shuffle cycle has played every queued track and Repeat is All Tracks, **When** the
   last track of the cycle ends (or the user taps Next), **Then** a new shuffled cycle begins whose
   first track is not the track that just played (with two or more queued tracks).
3. **Given** Shuffle on, **Then** the queue screen still lists the queue in its own order; turning
   Shuffle off continues from the current track in queue order.

---

### User Story 2 - Go back through what played (Priority: P1)

After skipping ahead in shuffle, the user taps Previous to hear the track they just skipped. Previous
walks back through the tracks that actually played, and Next then walks forward again through the
same tracks before new shuffled tracks.

**Why this priority**: The roadmap row's second half ("retain navigation history") and its acceptance
("Next and Previous follow a reproducible seeded shuffle sequence").

**Independent Test**: With a fixed seed, Next three times (A → B → C → D), then Previous twice gives
C, then B; Next twice gives C, then D; a further Next gives the next shuffled track.

**Acceptance Scenarios**:

1. **Given** Shuffle on and the history A, B, C with C playing for 3 seconds or less, **When** the user
   taps Previous, **Then** B plays from 0:00.
2. **Given** C playing for more than 3 seconds, **When** the user taps Previous, **Then** C restarts
   (the AUD-006-R16 rule is unchanged).
3. **Given** the user went back to B, **When** they tap Next, **Then** C plays again (the history,
   not a new shuffled track).
4. **Given** the first track in the history plays, **When** the user taps Previous within 3 seconds,
   **Then** that track restarts from 0:00.

---

### User Story 3 - Shuffle with each repeat mode (Priority: P2)

Shuffle and Repeat combine: Off stops after one full shuffled cycle; All Tracks reshuffles and goes
on; One Track repeats the current track while Next and Previous move through the shuffle.

**Why this priority**: The modes exist (AUD-004); their interplay must be defined.

**Independent Test**: For each mode, play a short shuffled queue to its end and check what follows.

**Acceptance Scenarios**:

1. **Given** Shuffle on and Repeat Off, **When** the last track of the cycle ends, **Then** playback
   stops and the first track of a new shuffled cycle waits at 0:00; Play starts it.
2. **Given** Shuffle on and Repeat One Track, **When** the track ends, **Then** it repeats; Next moves
   to the next shuffled track, which then repeats.
3. **Given** Shuffle on and Repeat All Tracks, **When** the last track of the cycle ends, **Then** a
   new cycle starts without repeating the track that just ended.

---

### User Story 4 - Turn Shuffle on and off, accessibly, and keep it (Priority: P2)

The user turns Shuffle on or off from a Shuffle button in the transport while an imported track plays
or from a Shuffle row in the queue screen. The choice and the shuffled order survive a relaunch.
VoiceOver reads "Shuffle" with the value "On" or "Off" and announces each change.

**Why this priority**: The control makes the feature reachable; persistence keeps a deliberate choice.

**Independent Test**: Turn Shuffle on from the queue screen, relaunch, read "On"; turn it off from
the transport while playing, relaunch, read "Off".

**Acceptance Scenarios**:

1. **Given** an imported track plays, **When** the user taps Shuffle, **Then** the value changes,
   VoiceOver announces it, and the playing track's position does not change and the audio is not cut.
2. **Given** the queue screen, **When** the user toggles Shuffle, **Then** the row shows the new
   value and the transport's Shuffle value matches.
3. **Given** Shuffle was turned on, **When** the app is relaunched, **Then** Shuffle is still on and
   the remaining shuffled order is the same as before the relaunch.
4. **Given** the reference track or a test signal plays, **Then** no Shuffle control is shown.

### Edge Cases

- One queued track: Shuffle on changes nothing; Next restarts it as today.
- Two queued tracks: the cycles alternate, never the same track twice in a row.
- A track added while shuffled (Play Next, Add to Queue, a new import) plays in this cycle: Play Next
  plays right after the current track; Add to Queue plays at the end of the cycle; an import joins the
  unplayed part at a position derived from the seed and its identifier.
- A queued track moved (reordered) while shuffled: the shuffled order does not change.
- A track removed while shuffled leaves the shuffled order and the history; the playing track removed
  plays to its end, then the next shuffled track follows (AUD-003-R9's rule in shuffled order).
- The queue cleared while shuffled: as AUD-003 (the playing track plays to its end; nothing follows).
- A track picked from the chooser while shuffled plays at once and counts as played in this cycle;
  the unplayed tracks stay unplayed.
- History entries whose track left the queue are skipped by Previous.
- The history is bounded (100 entries); the oldest entries are dropped.
- Shuffle toggled while paused, stopped or interrupted: only what follows changes; the state, the
  position and an automatic resume stay as they were (not a transport command).
- A stored record written by a newer app: Shuffle can be toggled for this launch, not stored
  (AUD-003-R14). A stored shuffle state that does not match the queue is repaired, never fatal.

## Requirements *(mandatory)*

### Functional Requirements

- **AUD-005-R1**: The app MUST offer a Shuffle setting (On or Off, default Off) for imported audio
  played from the queue. It belongs to the queue (one per device). With Shuffle Off, every AUD-003,
  AUD-004 and AUD-006 rule applies unchanged.
- **AUD-005-R2**: With Shuffle On, the play order MUST be a shuffled order (a permutation) of the
  queued tracks, made from a seed by a documented deterministic generator; the same seed and the same
  queue MUST always give the same order. The stored queue order MUST NOT change.
- **AUD-005-R3**: Turning Shuffle On while a track is current MUST make that track the first of the
  shuffled cycle (already played); the rest follows in shuffled order. Each queued track plays once per
  cycle unless the user moves back or picks a track.
- **AUD-005-R4**: Next and the end of a track MUST NOT select the track that just played, with two or
  more queued tracks, including across the start of a new cycle.
- **AUD-005-R5**: The app MUST keep a history of the tracks played while shuffled, at most 100 entries
  (the oldest dropped). Previous, within the 3-second rule of AUD-006-R16, MUST select the track before
  the current one in the history; at the start of the history it MUST restart the current track.
  After Previous, Next MUST move forward through the history before selecting new shuffled tracks.
- **AUD-005-R6** (repeat modes): All Tracks MUST start a new shuffled cycle (R4 applies) after the
  last track of a cycle; Off MUST stop after the last track of a cycle as AUD-004-R5 does, cueing the
  first track of a new cycle at 0:00, and Play then starts it (AUD-004-R6); One Track MUST repeat the
  current track at its end (AUD-004-R4) while Next and Previous follow R4 and R5. Next at the end of a
  cycle starts a new cycle in every mode (as Next wraps in every mode, AUD-004-R7).
- **AUD-005-R7** (edits while shuffled): adding, removing, reordering and clearing MUST keep the
  shuffled order a permutation of the queue: Play Next places the track right after the current one;
  Add to Queue places a newly queued track at the end of the cycle; a new import joins the unplayed
  part at a position derived from the seed; reordering does not change the shuffled order; removal
  takes the track out of the shuffled order and the history; the playing track removed plays to its end
  and the next unplayed shuffled track follows.
- **AUD-005-R8**: Picking a specific queued track to play MUST play it and count it as played in this
  cycle, leaving the unplayed tracks unplayed; it starts a new branch of the history (forward entries
  are dropped).
- **AUD-005-R9**: Turning Shuffle On or Off MUST NOT move the position, cut, restart or pause the
  playing track, and MUST NOT count as a transport command or a user transport change for interruption
  recovery (like AUD-004-R9). Turning it Off clears the history; Next and Previous then follow queue
  order from the current track.
- **AUD-005-R10**: The Shuffle setting, the seed, the cycle and the shuffled order with its played
  position MUST be stored with the queue (`queue.json`) at every change, with the atomic write, failure
  and newer-version rules of AUD-003-R13 and R14. The record change MUST be additive (no version
  change): with Shuffle Off nothing is written, so the record is byte-identical to AUD-004's; an older
  app ignores the fields. A stored shuffled order that is not a permutation of the stored queue MUST be
  repaired deterministically. The history within the current cycle is restored from the played
  position after a relaunch; older history is not stored.
- **AUD-005-R11**: The transport MUST show a Shuffle button while an imported track is the current
  item (not for the reference track or test signals). Its accessibility label MUST be "Shuffle", its
  value "On" or "Off", a change MUST be announced to VoiceOver, its icon MUST tell On from Off without
  relying on color alone, and it MUST stay usable at every Dynamic Type size.
- **AUD-005-R12**: The queue screen MUST show a Shuffle toggle (label "Shuffle", value On or Off) with a
  footer explaining it, reachable from the chooser and from the transport.
- **AUD-005-R13**: "Play Queue" with Shuffle On and no current track MUST start the first track of
  the shuffled order.
- **AUD-005-R14**: Nothing new runs on the real-time audio path (Constitution VII); the order is decided
  on the main actor. No network, no new dependency, public APIs only.
- **AUD-005-R15**: Behavior with real audio routes and interruptions on hardware MUST be checked on a
  physical device in the device phase (`{device}`); simulator and offline results are not device
  evidence.

### Key Entities

- **Shuffle state**: on or off, a seed, a cycle number, the shuffled order of the cycle and how much of
  it has played. Belongs to the queue.
- **Play history**: the tracks played while shuffled, in order, with a cursor at the current one;
  bounded to 100 entries.
- **Queue record** (`queue.json`, AUD-003/AUD-004): version 1, now with optional shuffle fields.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-005-S1** (roadmap acceptance): For a fixed seed, a scripted sequence of Next and Previous over a
  queue of five tracks produces exactly the expected track sequence in 100% of runs, and two runs with
  the same seed produce identical sequences.
- **AUD-005-S2**: Over 100 consecutive Next steps (20 cycles of five tracks) for representative seeds,
  no track follows itself and every cycle contains each queued track exactly once.
- **AUD-005-S3**: For each repeat mode, the step after the last track of a cycle is as R6 says in 100%
  of runs.
- **AUD-005-S4**: After each representative edit (add, Play Next, import, remove, remove current,
  reorder, clear) the shuffled order is a permutation of the queue and the next track is as R7 says.
- **AUD-005-S5**: Toggling Shuffle during playback keeps the position and the current track in 100% of
  runs; a Shuffle setting set from the UI is shown again after a relaunch in 100% of UI test runs.
- **AUD-005-S6**: A record with Shuffle Off encodes byte-identically to AUD-004's golden bytes; a record
  with Shuffle On round-trips; an AUD-004 decoder reads it.
- **AUD-005-S7**: Every AUD-003, AUD-004 and AUD-006 test still passes; each new unit test runs in
  about 1-2 s or less on the host (owner rule 7) and the new UI test in under 30 s.

## Assumptions

- One shuffle setting for the one queue; no per-playlist shuffle (there are no playlists).
- The playback position is still not stored; a relaunch restores the queue, the shuffle state and the
  current track, not playback (as AUD-003, AUD-004).
- Seeds for real use come from the system random number generator; tests always inject seeds.
- Interruption behavior (AUD-014) is unchanged.
