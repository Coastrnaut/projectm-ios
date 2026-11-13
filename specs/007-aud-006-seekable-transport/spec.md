# Feature Specification: AUD-006 Seekable transport

**Feature Branch**: `feature/aud-006` (spec directory `007-aud-006-seekable-transport`)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Implement AUD-006 (Seekable transport) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Provide play, pause, stop, next,
previous and scrubbing for owned audio." Acceptance, verbatim: "Seek within a test track updates
playback position and analysis without stale frames." Dependencies: AUD-001 (integrated). Honor the
repository constitution."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `AUD-006-R1…`, success criteria `AUD-006-S1…`, tasks `AUD-006-T01…`. Requirements
of feature 001 (`specs/001-ios-projectm-visualizer/spec.md`), of AUD-001
(`specs/003-aud-001-import-drm-free-audio-files/spec.md`), of AUD-002
(`specs/006-aud-002-support-common-audio-containers/spec.md`) and of PERF-011
(`specs/004-perf-011-background-resource-release/spec.md`) stay in force unless a line below amends
one explicitly.

## Clarifications

### Owner rulings 2026-11-12

- Owner ruling 2026-11-12 ("all recommended for policy choices"): with more than one imported track, the end of a track advances to the next track in the order and wraps; one track, and the reference track, repeat as before. Repeat modes stay with AUD-004.

### Session 2026-11-12

Answered by Claude under the owner's standing approval (routine decisions delegated, no human
interaction); each answer is the conservative, local-first option using public APIs only.

- Q: What should happen when a track reaches its end, now that one track no longer simply repeats forever? → A: Playback continues with the next track in the order and wraps from the last track to the first, so the visualizer never runs dry. With one track in the order (always the case for the reference track, and for a library of one) that track repeats without a gap, exactly as today. Nothing ends by itself; repeat modes that can end playback are AUD-004 (AUD-006-R17).
- Q: Which order do Next track and Previous track follow, and what happens at its ends? → A: The order of the "Your Audio" list as shown when the track was started (newest import first): Next goes down the list, Previous up, and both wrap around. Previous restarts the current track when it has played for more than 3 seconds. The order is a replaceable interface so that the AUD-003 queue can take its place (AUD-006-R14 to R16).
- Q: What does "stop" mean next to the existing Stop button, which leaves the visualizer? → A: The transport gets its own "Stop playback": sound stops and the position returns to 0:00, but the visualizer and the In-App Playback session stay. The existing Stop (back to the chooser) and the existing Pause (freeze the picture) keep their behavior and names. While playback is paused or stopped by the user the source status reads "Paused" for both, because the existing "Stopped" status means the source itself has ended (AUD-006-R5, R20, R23).
- Q: How is audio from before a seek kept away from the visualizer, given that audio is in transit in several places at that moment? → A: A seek is a hard cut: everything not yet delivered is discarded at every stage before delivery resumes (audio queued for output, audio on its way from the output mix to the analysis, audio waiting for analysis, the converter's leftover state, and audio waiting for the renderer), and delivery is closed while this happens so nothing slips through. No cross-fade and no gradual catch-up. The discard runs outside the real-time audio callback, which only gains a constant-time check (AUD-006-R10, R11, R28).
- Q: Does the scrubber seek continuously while it is dragged, or only when released? → A: Both, bounded: while dragging, playback follows the finger with at most 10 seeks per second, and the release always seeks to the exact final position. The times shown follow the finger immediately. With VoiceOver the scrubber moves in 10-second steps (AUD-006-R12, R26, R27).

## Baseline: what exists today (audit of 2026-11-12)

In-App Playback plays one track per session: the bundled reference track, or one track of the
user's imported library (AUD-001, AUD-002). It starts when the user picks it in the source chooser
and repeats that one track without end until the user taps Stop, which returns to the chooser.

| Capability | Today |
|---|---|
| Start a track | Yes, from the chooser only |
| Stop | Only by leaving the visualizer (Stop returns to the chooser) |
| Pause and continue the audio | No. "Pause" in the controls freezes the picture; the audio keeps playing |
| Move within a track | No |
| Go to another track without leaving the visualizer | No |
| See where playback is in the track | No |
| End of a track | The same track starts again, without a gap, forever |

Background, lock, interruptions and a lost output route already pause In-App Playback and are shown
truthfully (feature 001 FR-050, FR-051, FR-054; PERF-011). This feature adds the missing transport
and changes nothing else.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Jump to any point of my track and the picture follows at once (Priority: P1)

While one of the user's own tracks plays in the visualizer, the user drags a scrubber (or taps a
point on it) to move to another part of the track. The sound continues from the new point, the
elapsed and remaining times show the new point, and the visualization reacts to the audio at the
new point straight away: nothing from the part of the track that was playing before the jump is
shown after it.

**Why this priority**: This is the roadmap row's acceptance check. A visualizer that keeps drawing
audio from before a jump looks out of sync and makes scrubbing useless for finding a passage.

**Independent Test**: Play a generated test track whose every sample states its own position in the
track; jump to a known point; everything the visualizer's audio input receives after the jump comes
from that point onward, in order, and the reported position equals the point jumped to.

**Acceptance Scenarios**:

1. **Given** a track is playing, **When** the user jumps to a point in it, **Then** the reported
   position is that point and playback continues from it.
2. **Given** a jump was made, **When** audio next reaches the visualizer, **Then** it comes from
   the new point or later; no audio from before the jump arrives after it.
3. **Given** playback is paused, **When** the user jumps to a point, **Then** the position shows the
   new point, playback stays paused, and pressing Play continues from that point.
4. **Given** the user drags the scrubber quickly back and forth, **When** they let go, **Then**
   playback is at the point where they let go and nothing from an earlier point of the drag is shown
   afterwards.
5. **Given** the user jumps to the very start, **Then** playback is at 0:00; **given** a jump to or
   past the end, **then** the track counts as finished (User Story 3, scenario 4).

---

### User Story 2 - Play, pause and stop the audio without leaving the visualizer (Priority: P1)

The user pauses their track; sound stops, the position holds, and the status no longer says audio
is active. Play continues from the same point. Stop ends playback and returns to the start of the
track; Play then starts it from the beginning. The visualizer stays on screen throughout.

**Why this priority**: Play, pause and stop are the first three verbs of the roadmap row, and a
paused track that still claims "Active audio" would break truthful status (Constitution IV).

**Independent Test**: Play a track, pause for several seconds, and resume: the position did not
move while paused and the status showed "Paused"; stop: the position is 0:00 and Play starts from
the beginning.

**Acceptance Scenarios**:

1. **Given** a track is playing, **When** the user taps Pause, **Then** sound stops, no
   further audio is delivered to the visualizer, the position stops advancing, and the source status reads "Paused" (never "Active
   audio").
2. **Given** playback is paused, **When** the user taps Play, **Then** playback continues from the
   paused position and the status returns to "Active audio" once sound is verified again.
3. **Given** a track is playing or paused, **When** the user taps Stop playback, **Then** sound
   stops, the position is 0:00, and the visualizer stays on screen.
4. **Given** playback is stopped, **When** the user taps Play, **Then** the track plays from the
   beginning.
5. **Given** the user paused or stopped playback, **When** the app goes to the background and
   comes back, or the device is locked and unlocked, **Then** playback is still paused or stopped;
   it does not start on its own.
6. **Given** a track is playing, **When** the app goes to the background and returns, **Then**
   playback behaves exactly as before this feature (it is paused while away and continues on
   return) and continues from where it was.

---

### User Story 3 - Next and previous track (Priority: P2)

With several imported tracks, the user moves to the next or the previous track without going back
to the chooser. The order is the order of the "Your Audio" list. When a track ends by itself, the
next one starts, and after the last one the first starts again, so the visualizer never runs dry.

**Why this priority**: Completes the roadmap row's verbs. It depends on the transport of stories 1
and 2 and is less critical than seek correctness.

**Independent Test**: Import three tracks, play the first, tap Next twice and Previous once: the
track titles follow the list order; let a short track end: the next one starts.

**Acceptance Scenarios**:

1. **Given** a track from "Your Audio" is playing, **When** the user taps Next track, **Then** the
   track below it in the list starts from 0:00; from the last track, the first one starts.
2. **Given** a track has played for more than 3 seconds, **When** the user taps Previous track,
   **Then** the same track restarts from 0:00.
3. **Given** a track has played for 3 seconds or less, **When** the user taps Previous track,
   **Then** the track above it in the list starts from 0:00; from the first track, the last one
   starts.
4. **Given** a track reaches its end while playing, **Then** the next track in the order starts
   from 0:00; when there is only one track in the order it starts again without a gap, as today.
5. **Given** playback is paused or stopped, **When** the user taps Next track or Previous track,
   **Then** the other track is selected at 0:00 and stays paused or stopped until Play.
6. **Given** the next track's stored copy is missing or no longer plays, **When** it is reached,
   **Then** playback ends with "In-App Playback failed" (AUD-001-R19, AUD-002-R12); no other track
   is played in its place.
7. **Given** the bundled reference track is playing, **Then** Play, Pause, Stop playback and the
   scrubber work the same way; Next track and Previous track restart the reference track, because
   it is the only track in its order.

---

### User Story 4 - Transport controls that fit the visualizer and work for everyone (Priority: P2)

The transport appears with the other visualizer controls, only when the user's own audio or the
reference track is playing in the app. It hides with the controls, does not cover more of the
picture than necessary, scales with the text size, and every control, including the scrubber, can
be operated with VoiceOver.

**Why this priority**: The controls are how every other story is reached; they must not appear for
sources they cannot control, and must be accessible (feature 001 FR-070).

**Independent Test**: Start In-App Playback: the transport shows. Start Microphone or System/App
Capture: no transport. With VoiceOver, move the scrubber with the increment and decrement gestures.

**Acceptance Scenarios**:

1. **Given** In-App Playback of the user's audio or the reference track, **When** the controls are
   visible, **Then** they include the track title, Previous track, Play or Pause, Stop playback,
   Next track, a scrubber, and the elapsed and remaining time.
2. **Given** Microphone or System/App Capture is the source, **Then** no transport control is shown
   and no transport action has any effect on that source.
3. **Given** the controls hide after their usual delay, **Then** the transport hides with them; a
   tap brings both back; using a transport control restarts the delay.
4. **Given** VoiceOver is on, **Then** each transport control states its meaning; the scrubber
   states the elapsed time and the track length and moves by a fixed step with the increment and
   decrement gestures.
5. **Given** a large accessibility text size or a narrow window, **Then** the transport stays
   usable: times remain readable and no control is cut off.

---

### Edge Cases

- A jump while the track is changing (Next was just tapped, or the track just ended): the jump
  applies to the track that is current when it is handled; audio of the previous track never
  appears after the change.
- Many jumps in quick succession (scrubbing): only the last one decides where playback continues;
  intermediate points may be skipped.
- A jump to a negative time is treated as 0:00; a time past the end as the end.
- A jump to the end while paused or stopped: the position shows the end; Play then continues with
  the next track in the order (or the same track from 0:00 when it is the only one).
- Pause pressed twice, Play pressed while playing, Stop playback pressed while stopped: no effect.
- Pause while an interruption (for example a call) or a lost output route has already paused
  playback: playback stays paused afterwards until the user presses Play; the existing banner's
  Resume does the same as Play.
- The existing Stop button still stops the source and returns to the chooser; the existing Pause
  button still freezes the picture only. Both are unchanged; the transport's buttons have their own
  names.
- Tracks of different sample rates or channel counts in a row: each plays at its own pitch and
  speed (AUD-002-R3); a short silence between two different tracks is acceptable.
- A track shorter than a second: all controls work; reaching the end follows the normal rule.
- A very long track (hours): the times are shown as `h:mm:ss`; jumping stays immediate.
- Nothing is persisted: the position and the paused state are not restored after the app is
  closed, and a new session always starts playing from 0:00.

## Requirements *(mandatory)*

### Functional Requirements

**Scope**

- **AUD-006-R1**: The transport MUST apply only to In-App Playback: tracks of the user's imported
  library and the bundled reference track ("owned audio"). It MUST NOT be offered for, or act on,
  System/App Capture or Microphone.
- **AUD-006-R2**: Every track played through the transport MUST remain labeled "In-App Playback"
  (Constitution IV, AUD-001-R18). Changing track MUST NOT change the source label or start a new
  source session.

**Transport state**

- **AUD-006-R3**: Playback MUST be in exactly one of three states: playing, paused, or stopped.
  A new In-App Playback session starts playing at 0:00, as today.
- **AUD-006-R4**: Pause MUST stop the sound and hold the position. Play from paused MUST continue
  from the held position: the position after resuming differs from the position at the pause by no
  more than 50 ms.
- **AUD-006-R5**: Stop playback MUST stop the sound and set the position to 0:00 while the
  visualizer stays on screen and the source session stays open. Play from stopped MUST start the
  current track from 0:00.
- **AUD-006-R6**: The transport MUST expose, for the current track: its title, its duration, and
  the current position, with the position never below 0 and never above the duration.
- **AUD-006-R7**: Commands that do not apply in the current state (Pause while paused or stopped,
  Play while playing, Stop playback while stopped) MUST have no effect and MUST NOT fail.

**Seek**

- **AUD-006-R8**: Seek MUST accept any time; times below 0 are treated as 0 and times above the
  duration as the duration. It MUST work while playing, paused and stopped. Seeking while stopped
  leaves playback paused at the new position.
- **AUD-006-R9**: Immediately after a seek the reported position MUST equal the requested position
  (after clamping) within 50 ms, and while playing it MUST then advance from there.
- **AUD-006-R10**: After a seek, the first audio delivered for analysis and visualization MUST be
  the track's audio at the requested position, and everything delivered after it MUST follow in
  track order. No audio that was read, queued or in transit before the seek may be delivered to the
  analysis or to the visualizer after it. The same holds for a track change made by the user
  (Next track, Previous track), Stop playback, and Play after pause. The automatic change at the
  end of a track is not a jump: the finished track is delivered to its last frame, then the next
  track from its first, in that order.
- **AUD-006-R11**: Levels shown for the source MUST NOT be computed from audio from before the
  seek once the seek has been handled.
- **AUD-006-R12**: When several seeks arrive in quick succession, the last one MUST decide the
  position; the app MUST stay responsive and MUST NOT queue an unbounded number of seeks. While
  the scrubber is dragged, at most 10 seeks per second are made, and releasing it always seeks to
  the exact final position.
- **AUD-006-R13**: A seek to the end of the track (or beyond) MUST be treated as the track having
  finished: while playing, the end-of-track rule applies at once (AUD-006-R17); while paused or
  stopped, the position shows the end and the rule applies when Play is pressed.

**Next, previous and the end of a track**

- **AUD-006-R14**: The play order is the order in which "Your Audio" lists the tracks at the moment
  playback of a library track is started from the chooser. For the reference track the order
  contains only the reference track. The order MUST sit behind an interface that a later queue
  feature (AUD-003) can replace without changing the transport.
- **AUD-006-R15**: Next track MUST select the track after the current one in the order, at 0:00;
  after the last track it selects the first.
- **AUD-006-R16**: Previous track MUST restart the current track at 0:00 when its position is
  greater than 3 seconds; otherwise it selects the track before the current one, at 0:00, and from
  the first track the last.
- **AUD-006-R17**: When a track reaches its end while playing, playback MUST continue with the
  track after it in the order (wrapping from last to first). When the order holds one track, that
  track MUST repeat without an audible gap, as before this feature. With the play order of this
  feature playback never ends by itself; an order that reports that nothing follows (reserved for
  AUD-004) leaves the transport stopped at the end of the track.
- **AUD-006-R18**: Next track, Previous track and the automatic change keep the transport state:
  playing stays playing; paused or stopped stays so, with the new track at 0:00.
- **AUD-006-R19**: When the track to change to cannot be opened or decoded, the session MUST end
  with "In-App Playback failed" (AUD-001-R19, AUD-002-R12). No other track is substituted and no
  silence is played.

**Truthful status and lifecycle**

- **AUD-006-R20**: While playback is paused or stopped by the user, the source status MUST read
  "Paused"; it MUST NOT read "Active audio", "Waiting", "Audio received — silent" or "No audio
  received", and no "no sound" hint may be shown. After Play, "Active audio" is shown only once
  non-silent audio is verified again (feature 001 FR-011).
- **AUD-006-R21**: Playback paused or stopped by the user MUST stay so across background,
  foreground, lock, unlock and the end of an interruption; only the user's Play (or the existing
  Resume action) continues it.
- **AUD-006-R22**: For playback that is playing, the existing behavior on background, lock,
  interruption and lost output route MUST be unchanged (feature 001 FR-050, FR-051, FR-054;
  PERF-011), and playback MUST continue from the position at which it was paused.
- **AUD-006-R23**: The existing Stop control (stop the source, return to the chooser) and the
  existing Pause control (freeze the picture) MUST keep their behavior and names.

**Controls**

- **AUD-006-R24**: When In-App Playback is the active source, the visualizer controls MUST include:
  the current track's title, Previous track, Play (when paused or stopped) or Pause playback (when
  playing), Stop playback, Next track, a scrubber, the elapsed time and the remaining time. For
  other sources none of these is shown.
- **AUD-006-R25**: The transport controls MUST appear and hide with the existing controls
  (feature 001 FR-042), and every use of one MUST restart the hide delay. They MUST NOT cover the
  visualization while the controls are hidden.
- **AUD-006-R26**: Every transport control MUST have an accessibility label stating its meaning.
  The scrubber MUST be adjustable with the VoiceOver increment and decrement gestures in steps of
  10 seconds (clamped to the track), and MUST state the elapsed time and the track's length as its
  value. All text MUST scale with the system text size (feature 001 FR-070).
- **AUD-006-R27**: While the user drags the scrubber, the elapsed and remaining times MUST show
  the dragged position. Exact strings: `contracts/ui-strings.md`.

**Safety, privacy and compliance**

- **AUD-006-R28**: Nothing added by this feature may allocate memory, take a lock, perform file
  or network I/O, or log inside a real-time audio callback (Constitution VII). Discarding stale
  audio MUST be bounded in time.
- **AUD-006-R29**: Rapid sequences of transport commands (including Stop to the chooser during a
  seek or a track change) MUST NOT crash, deadlock, leave two tracks playing, or leave audio
  playing after the source was stopped.
- **AUD-006-R30**: The feature MUST use only public platform APIs, no network, no new permission,
  entitlement or background mode, and no new dependency. It stores nothing: no position, state or
  order is written to disk, and no audio is recorded.

### Key Entities

- **Transport**: the playback state of the In-App Playback session: state (playing, paused,
  stopped), current track, position, duration.
- **Playable item**: one entry of the play order: a stable identity, a title, a duration, and the
  track it plays (a library track or the reference track).
- **Play order**: an ordered list of playable items that answers "what comes after this item" and
  "what comes before it"; in this feature, the "Your Audio" list order with wrap-around.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-006-S1**: With a generated test track whose samples state their own position, after a seek
  to position P while playing, 100% of the audio that reaches the analysis input and the
  visualizer's audio input after the seek comes from P or later and is in track order, with the
  first delivered sample exactly at P. (Roadmap acceptance.)
- **AUD-006-S2**: After a seek the reported position equals the requested position within 50 ms,
  for seeks while playing, paused and stopped, to 0, to the middle, to the end and beyond the end.
- **AUD-006-S3**: After 100 seeks in quick succession to different positions, playback is at the
  last requested position and no audio from any earlier position is delivered afterwards.
- **AUD-006-S4**: A pause of any length changes the position by no more than 50 ms, and the status
  reads "Paused" for the whole pause in 100% of checks.
- **AUD-006-S5**: Next track and Previous track follow the documented order in 100% of cases,
  including both ends of the list and the 3-second rule, and after a track change no audio of the
  previous track is delivered.
- **AUD-006-S6**: A user can pause, resume, stop, restart, change track and jump within a track
  without leaving the visualizer, and every transport control is reachable and operable with
  VoiceOver.
- **AUD-006-S7**: Existing behavior is intact: all existing tests for capture, lifecycle, imported
  audio and status pass unchanged or with a recorded, justified update.

## Assumptions

- "Owned audio" means In-App Playback content: the user's imported library (AUD-001) and the
  bundled reference track. Audio captured from other apps or the microphone is not owned and has no
  transport.
- The play order comes from the library list as shown (newest import first). A persistent,
  reorderable queue is AUD-003; repeat modes are AUD-004; shuffle is AUD-005. Until AUD-004 offers
  a choice, playback continues around the order (the behavior AUD-004 will call "repeat all"),
  which for a single track is today's endless repeat.
- The reported position is the position of the audio handed to the device's output; the delay of
  the output hardware (for example wireless headphones) is not compensated. Compensation is part of
  AUD-013 and PERF-013.
- The visualizer engine keeps a short history of audio it has already received in order to draw;
  that history is not erased by a seek. The requirement is about what is delivered after the seek.
- Lock-screen and Control Center transport controls, remote commands from headphones, and playback
  while the app is in the background are outside this feature (AUD-015 decides the background
  policy; no background mode is added here).
- The interruption policy (when to resume after a call) is AUD-014; this feature keeps today's
  behavior and only guarantees that a user's pause is respected.
- English-only strings, as in features 001, AUD-001 and AUD-002.
- Physical-device checks (output routes, interruptions and real-time behavior of seeking on
  hardware) happen in the roadmap's final device phase and are tagged `{device}` in tasks.
  Simulator and Mac results are not device evidence (Constitution X).
