# Feature Specification: AUD-014 Audio session interruption recovery

**Feature Branch**: `feature/aud-014` (spec directory `009-aud-014-audio-session-interruption-recovery`)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Implement AUD-014 (Audio session interruption recovery) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Resume eligible in-app audio
only when interruption policy permits." Acceptance, verbatim: "Synthetic interruption and real
phone call restore correct transport state." Dependencies: none (extends the existing capture
lifecycle and the AUD-006 transport). Honor the repository constitution."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `AUD-014-R1…`, success criteria `AUD-014-S1…`, tasks `AUD-014-T01…`. Requirements
of feature 001 (`specs/001-ios-projectm-visualizer/spec.md`, in particular FR-015, FR-050, FR-051,
FR-053, FR-054, FR-055 and FR-070), of AUD-001, AUD-002, PERF-011 and of AUD-006
(`specs/007-aud-006-seekable-transport/spec.md`, in particular AUD-006-R10, R20 and R21) stay in
force. This feature cites them and adds to them; where it narrows how one applies, the line says so.

## Clarifications

### Owner rulings 2026-11-12

- Owner ruling 2026-11-12 ("all recommended for policy choices"): when an interruption ends while the app is in the background, or iOS never reports its end, nothing resumes by itself; the user presses Play.
- Owner ruling 2026-11-12 ("all recommended for policy choices"): the feature keeps using `AVAudioSession.interruptionNotification`, deprecated in the iOS 27 SDK but the only notification on iOS 26; moving to the iOS 27 notifications is decided after device task T29.

### Session 2026-11-12

Answered by Claude under the owner's standing approval (routine decisions delegated, no human
interaction); each answer is the conservative, local-first option using public APIs only.

- Q: When the user returns to the app while an interruption is still open (or after one ended without a resume indication), should playback resume as FR-050 does after an ordinary background? → A: No. It stays on hold and shows the "Interrupted" reason until iOS indicates a resume or the user presses Play. Resuming blindly would try to play over a call that is still going on. Without an interruption FR-050 is unchanged (AUD-014-R5, R6).
- Q: Does a seek or a track change by the user during an interruption cancel the automatic resume, like a pause does? → A: Yes. Any transport action during the interruption (pause, Stop playback, seek, next, previous) means the user has taken over: playback stays on hold at the user's last choice and Play continues (AUD-014-R2).
- Q: After an interruption ended without a resume indication, should the status change to "Paused" or keep feature 001's "Interrupted" with Restart? → A: Keep FR-051 exactly: "Interrupted" with Restart and Choose source. This feature adds an explanation line and guarantees that Play continues from the held position; it adds no state and no stop reason (AUD-014-R7, R17, R23).
- Q: After iOS resets its media services while a track was playing, should playback continue by itself or wait for the user? → A: It is rebuilt and continues from the held position when it was playing and no interruption was open, because a reset is a fault inside iOS and not a request for silence; in every other state it stays on hold. If it cannot be rebuilt the session ends with "In-App Playback failed" (AUD-014-R16).
- Q: iOS 27 introduces new notices for "session became inactive" and "resumption recommended" and marks the older interruption notice as deprecated from 27.0; which does the app rely on? → A: The older interruption notice with its type, option and reason values, because it is the only one available on every supported version (iOS 26.0 and later) and using both would report each interruption twice on iOS 27. The suspended-app marker is not relied on (the SDK documents that it is no longer sent from iOS 16). That the older notice still arrives on iOS 27 devices is checked in the device phase; moving to the new notices is a follow-up if it does not (Assumptions, AUD-014-S6).

## Baseline: what exists today (audit of 2026-11-12, commit `e40e578`)

This is an extension row: most of the interruption handling exists. The audit below is per event
and per source. "In-App" covers the reference track and imported tracks alike; both go through the
same playback path and the AUD-006 transport.

| Event | In-App Playback today | Microphone today | System/App Capture today |
|---|---|---|---|
| Interruption began | Status becomes "Interrupted"; the sound stops because iOS stops the audio. The app does not hold the playback position itself: the transport shows the position the controls last read, or the start of the current segment when the controls were hidden (the staleness the AUD-006 report describes) | Status "Interrupted" | No change while the stream delivers (FR-051) |
| Interruption ended, iOS says audio may resume | Resumes, but also when the user moved the transport (seek, next, previous) during the interruption. A user pause during the interruption is respected (AUD-006-R21) | Resumes | No change |
| Interruption ended, no resume indicated | Stays "Interrupted" with Restart and Choose source (FR-051); Play continues | Stays "Interrupted" with one-tap Restart | No change |
| Interruption never ends | Stays "Interrupted". Play is tried; if iOS refuses to give the audio back, the whole session ends as "In-App Playback failed" and the track and position are lost | Stays "Interrupted" | No change |
| Interruption began as a late notice that the app had been suspended | Not told apart from a real interruption. The SDK documents that this notice is no longer sent from iOS 16 on; the app's minimum is iOS 26 | Same | No change |
| App goes to the background or the device locks during an interruption | The status becomes "Paused" (the reason line still reads "Interrupted") and the fact that an interruption is open is not used. On return to the foreground playback resumes at once, whether or not the interruption has ended and whether or not iOS said audio may resume | Same | Keeps running (RI-003) |
| Output device disconnected (headphones unplugged) | Pauses, "Paused — audio route changed", Resume continues (FR-051). But when it happens during an interruption or while the app is in the background it is not recorded, and playback later resumes by itself on the new output | Continues on the new input, or "Microphone unavailable" | Not applicable |
| Audio hardware configuration changes (for example another output with another sample rate) | Not handled: iOS stops the app's audio engine, the app does not restart it, and the status later reads "No audio received" while the transport still shows "playing" | Not handled separately (a route change restarts the input) | Not applicable |
| Media services were reset by iOS | Not handled: playback is dead until the user leaves and starts again | Ends with a visible error | Not applicable |
| User leaves the visualizer (Stop) during an interruption | The session ends; later events are ignored | Same | Same |

What is missing, and is this feature: one explicit, testable resume policy; the exact position at
the moment of the interruption; no blind resume after the background; no resume after the user
moved the transport or the output was lost during the interruption; a session that survives a
refused Play; recovery from a hardware configuration change and from a media-services reset; and a
visible, accessible explanation of why playback is on hold.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - My music comes back after a call, exactly where it was (Priority: P1)

The user plays one of their own tracks in the visualizer. A phone call, an alarm or Siri interrupts
the audio. The status shows that playback is interrupted and the transport shows paused at the
moment the sound stopped. When the interruption ends and iOS indicates that audio may resume,
playback continues by itself from that moment: same track, same play order, and the picture reacts
only to audio from after the interruption.

**Why this priority**: This is the roadmap row. Without it a call either loses the listener's
place or leaves a visualizer that claims to play while nothing is heard.

**Independent Test**: Play an imported track, deliver a synthetic interruption, check the status
and the transport during it, deliver its end with the resume indication, and check that playback
continues from the held position with no audio from before the interruption.

**Acceptance Scenarios**:

1. **Given** an imported track is playing at 0:42, **When** an interruption begins, **Then** within
   1 second the status reads "Interrupted", the transport shows Play (not Pause) and the position
   stays within 0.25 seconds of 0:42, whether or not the controls were visible before.
2. **Given** that interruption, **When** it ends and iOS indicates audio may resume, **Then** within
   2 seconds playback continues from the held position in the same track, the status passes through
   "Waiting" and reads "Active audio" only after new audio was verified.
3. **Given** playback resumed after an interruption, **When** the picture reacts, **Then** it reacts
   only to audio from the held position on; nothing from before the interruption is shown.
4. **Given** the reference track is playing, **When** the same sequence happens, **Then** the result
   is the same.

---

### User Story 2 - The app never starts sound I did not ask for (Priority: P1)

The user paused, or stopped playback, or dragged the scrubber, or skipped to another track while an
interruption was open; or the interruption ended without iOS indicating a resume; or the headphones
were unplugged during the call. In all of these cases the app stays silent after the interruption.
The transport shows paused (or stopped) at the right position and one tap on Play continues.

**Why this priority**: Sound that starts by itself (in a meeting, from the speaker after the
headphones were unplugged) is the failure users forgive least. It is the "only when the policy
permits" half of the row.

**Independent Test**: For each condition, deliver the interruption and its end and check that
playback did not start, the position is right and Play continues from it.

**Acceptance Scenarios**:

1. **Given** the user paused before the interruption, **When** the interruption ends with the
   resume indication, **Then** playback stays paused at the same position.
2. **Given** the user pressed Stop playback before the interruption, **When** it ends, **Then** the
   transport still shows stopped at 0:00.
3. **Given** playback was interrupted while playing, **When** the user pauses, stops playback,
   seeks or changes the track during the interruption and it then ends with the resume indication,
   **Then** playback does not start; the transport shows the user's last choice of track and
   position, and Play continues from there.
4. **Given** playback was interrupted while playing, **When** the interruption ends without the
   resume indication, or never ends, **Then** the status stays "Interrupted" with Restart and Choose
   source (FR-051), the transport shows paused at the held position, and Play continues from it.
5. **Given** an interruption is open, **When** the output device is disconnected and the
   interruption then ends with the resume indication, **Then** playback does not start and the
   status reads "Paused — audio route changed".
6. **Given** no session, or a session that was not interrupted, **When** an "interruption ended"
   event arrives, **Then** nothing changes and nothing starts.

---

### User Story 3 - Coming back to the app during or after an interruption (Priority: P2)

The user answers a call, which sends the app to the background, and later returns. If the call is
still going on, the app stays on hold instead of trying to play over it. If the call has ended and
iOS indicated a resume, playback continues when the app is visible again. If the user taps Play
while the call still holds the audio, the tap may not succeed, but the track and the position are
kept.

**Why this priority**: It is the real phone-call path. It needs the first two stories.

**Independent Test**: Deliver interruption began, background, foreground and interruption ended in
each order and check the state after each step.

**Acceptance Scenarios**:

1. **Given** an open interruption of playing audio, **When** the app goes to the background and
   returns before the interruption ended, **Then** playback does not resume on return; the status
   shows "Paused" with the "Interrupted" reason.
2. **Given** that state, **When** the interruption ends with the resume indication while the app is
   in the foreground, **Then** playback resumes from the held position.
3. **Given** an open interruption, **When** it ends with the resume indication while the app is in
   the background, **Then** nothing plays in the background and playback resumes within 2 seconds
   of the return to the foreground.
4. **Given** an open interruption, **When** the user taps Play and iOS refuses to give the audio
   back, **Then** the session stays, with the same track and position and the "Interrupted" status;
   it does not end as "In-App Playback failed".
5. **Given** no interruption, **When** the app goes to the background and returns, **Then** it
   resumes exactly as before this feature (FR-050), and a user pause is still never resumed
   (AUD-006-R21).

---

### User Story 4 - Playback survives a change of the audio hardware (Priority: P2)

While a track plays, the audio hardware changes its configuration (the user connects an output
with another sample rate), or iOS resets its media services. Playback continues at the same place
without the user doing anything; if it was paused or interrupted it stays so with its position; if
it cannot be rebuilt the user sees "In-App Playback failed".

**Why this priority**: Without it a route change can leave a visualizer that shows "playing" with
no sound. It is less frequent than a call.

**Independent Test**: Stop the audio engine as iOS does, deliver the configuration-change (or
reset) notice, and check position, state and that no audio from before the restart is delivered.

**Acceptance Scenarios**:

1. **Given** a track is playing, **When** the audio hardware configuration changes, **Then**
   playback continues within 1 second from the position it had (within 0.25 seconds), in the same
   track, and nothing from before the restart reaches the picture.
2. **Given** playback is paused, stopped or interrupted, **When** the configuration changes or media
   services are reset, **Then** it stays paused, stopped or interrupted at the same position, and a
   later Play continues from it.
3. **Given** a track is playing, **When** media services are reset, **Then** playback is rebuilt
   and continues from the position it had, in the same track with the same play order.
4. **Given** media services were reset, **When** playback cannot be rebuilt, **Then** the session
   ends with "In-App Playback failed" and no other track plays instead.

---

### User Story 5 - I can tell why it is quiet, also with VoiceOver (Priority: P3)

Whenever playback is on hold for a reason the user did not choose, the visualizer says why in
words: interrupted, or paused because the audio output was disconnected, and that Play continues.
VoiceOver announces the change.

**Why this priority**: The states exist; the explanation makes them understandable.

**Independent Test**: Put In-App Playback in each state and read the status text and the
VoiceOver announcement.

**Acceptance Scenarios**:

1. **Given** In-App Playback is interrupted, **When** the user looks at the visualizer, **Then**
   next to "Interrupted" an explanation says that playback is on hold at its position and how it
   continues.
2. **Given** In-App Playback was paused because the output was disconnected, **When** the user
   looks, **Then** next to "Paused — audio route changed" an explanation says that the audio output
   was disconnected and that Play continues.
3. **Given** VoiceOver is on, **When** playback becomes interrupted or is paused by a disconnected
   output, **Then** VoiceOver announces the new status with its explanation.
4. **Given** Microphone or System/App Capture is the source, **When** it is interrupted, **Then**
   its texts are exactly those of feature 001.

---

### Edge Cases

- "Interruption ended" arrives before "began" was handled, or without any "began": ignored; a
  "began" that follows opens an interruption that waits for its own end.
- "Began" twice in a row: one interruption; the position and the state before it are those of the
  first.
- Two interruptions back to back: when the first ended without a resume indication, the second
  cannot make playback resume (nothing was playing when it began).
- Interruption during a seek or a track change: the position after the interruption is the one the
  user chose last.
- Interruption while the track is at its end and the next track is being loaded: no track is
  skipped and none is played twice.
- Media-services reset or hardware change during an interruption: the session stays on hold at its
  position.
- The user leaves to the source chooser during an interruption and starts another source: events
  of the old session change nothing.
- The source is stopped and started again many times: every session reacts to each event exactly
  once.
- The output device is disconnected while the app is in the background: playback does not resume
  by itself on return.
- An interruption with the "route disconnected" reason: treated as an interruption during which
  the output was lost.
- Resuming is permitted but playback cannot be started: "In-App Playback failed" (FR-015).

## Requirements *(mandatory)*

### Functional Requirements

**Policy**

- **AUD-014-R1**: The resume decision for interrupted audio MUST come from one documented policy
  with these inputs: the kind of source; the transport state before the interruption (playing,
  paused, stopped); who holds playback paused (nobody, the user, the system because the output was
  lost); what iOS has indicated (interruption still open, ended without a resume indication, ended
  with one, or no interruption); whether the app is in the foreground and unlocked; whether the
  user changed the transport during the interruption; and whether the source can still be used. Its
  outcomes are: resume, stay paused, stay stopped, or fail with a visible reason. Every combination
  of inputs MUST have exactly one outcome.
- **AUD-014-R2**: In-App Playback MUST resume by itself after an interruption only when all of the
  following hold: it was playing before the interruption because the user started it; iOS indicated
  that audio may resume; the user did not pause, stop playback, seek or change the track during the
  interruption; the output was not lost during the interruption; the app is in the foreground and
  unlocked; and it is still the same session.
- **AUD-014-R3**: A pause or Stop playback by the user MUST never be undone by the end of an
  interruption, a return to the foreground, a hardware change or a media-services reset
  (AUD-006-R21 extended to every recovery path).
- **AUD-014-R4**: Nothing MUST start playing that was not playing when the interruption began. An
  "interruption ended" without an open interruption changes nothing. A second "began" during an
  open interruption changes nothing. An interruption that begins while playback is on hold after an
  earlier interruption that ended without a resume indication cannot make playback resume.
- **AUD-014-R5**: When iOS indicated a resume while the app was in the background or locked,
  playback MUST NOT start there; it MUST resume within 2 seconds of the app being in the foreground
  and unlocked again, if AUD-014-R2 still holds.
- **AUD-014-R6**: A return to the foreground or an unlock MUST NOT resume playback while an
  interruption is open or after one ended without a resume indication. This narrows how FR-050's
  automatic resume applies to In-App Playback: the state then shows the FR-015 reason
  ("Interrupted") instead. Without an interruption FR-050 applies unchanged.
- **AUD-014-R7**: When an interruption ended without a resume indication, or does not end, In-App
  Playback MUST stay on hold with the "Interrupted" status and its actions (FR-051); Play (and the
  transport's Play/Pause button) MUST continue from the held position.
- **AUD-014-R8**: When the user asks to play during an open interruption and iOS refuses, the
  session MUST stay as it was (same track, position, play order, "Interrupted"); it MUST NOT end as
  failed. When resuming is permitted by the policy, or asked for by the user with no interruption
  open, and playback cannot be started, the session MUST end with "In-App Playback failed"
  (FR-015) and no other track may play instead.
- **AUD-014-R9**: Microphone and System/App Capture MUST behave exactly as before this feature
  (FR-050, FR-051, FR-053, FR-055, ADR-0001): Microphone resumes when iOS indicates it may and
  otherwise shows "Interrupted" with a one-tap restart; System/App Capture is not changed by an
  interruption and is never restarted without the system picker. The policy states these outcomes;
  it does not change them.

**Transport state**

- **AUD-014-R10**: When an interruption begins while In-App Playback plays, the app MUST hold the
  playback position of that moment itself: within 0.25 seconds of the audio last heard, and
  independent of whether the controls were visible or when the position was last displayed.
- **AUD-014-R11**: After a resume the track, the play order and the position MUST be those held
  (or those the user chose during the interruption, when the user then presses Play), and the
  transport MUST show playing. After a non-resume the transport MUST show paused, or stopped at
  0:00 when the user had stopped playback, at that position.
- **AUD-014-R12**: Every restart of playback under this feature (resume after an interruption,
  after a hardware change, after a media-services reset) MUST be a hard cut as defined by
  AUD-006-R10: no audio from before it reaches the analysis or the picture afterwards.
- **AUD-014-R13**: The status MUST stay truthful (Constitution IV): never "Active audio" while
  playback is interrupted or paused; after a resume "Waiting" until new audio is verified.

**Output route**

- **AUD-014-R14**: When the output device is disconnected, In-App Playback MUST pause with "Paused
  — audio route changed" (FR-051) and MUST NOT resume by itself: not when an interruption ends,
  and not on a return to the foreground. This also holds when the disconnection happens during an
  interruption or while the app is in the background. Play or Resume continues.

**Hardware changes and resets**

- **AUD-014-R15**: When the audio hardware configuration changes while In-App Playback plays,
  playback MUST continue within 1 second from the position it had (AUD-014-R10's accuracy), in the
  same track. While it is paused, stopped or interrupted it MUST stay so, keep its position, and a
  later Play MUST work.
- **AUD-014-R16**: When iOS resets its media services, In-App Playback MUST rebuild its playback
  and restore the track, the position and the play order; it continues playing only if it was
  playing and no interruption was open, and otherwise stays on hold. If it cannot be rebuilt the
  session MUST end with "In-App Playback failed".

**What the user sees and hears**

- **AUD-014-R17**: While In-App Playback is interrupted, and while it is paused because the output
  was disconnected, the visualizer MUST show an explanation in addition to the feature 001 status
  texts: that playback is on hold at its position and that Play continues. The texts are defined
  in this feature's string contract and exist once in the app's string table.
- **AUD-014-R18**: VoiceOver MUST announce when In-App Playback becomes interrupted and when it is
  paused by a disconnected output, with that explanation (FR-070 extended).
- **AUD-014-R19**: The texts and actions of Microphone and System/App Capture MUST NOT change.

**Robustness, safety, privacy**

- **AUD-014-R20**: Interruption, route, lifecycle, hardware and reset events MUST be safe in any
  order and any repetition: no crash, never two playbacks at once, never a resume of a session the
  user left. Each session reacts to each event exactly once, also after the source was stopped and
  started again (Constitution VII).
- **AUD-014-R21**: Nothing this feature adds may block, allocate or wait on a real-time audio
  callback (Constitution VII).
- **AUD-014-R22**: The feature MUST NOT add a permission, an entitlement, a background mode, a
  network use or stored data, and MUST use public APIs only (Constitution I, Privacy). Playback
  still starts only after the user's own action; a resume continues what the user started.
- **AUD-014-R23**: The diagnostics export keeps its vocabulary: no new state, stop reason or
  lifecycle event name.

### Key Entities

- **Interruption policy**: the decision table of AUD-014-R1. Inputs and outcomes only; it holds no
  state and touches no audio.
- **Open interruption**: what the app remembers from "began" until playback resumes or the session
  ends: whether playback was eligible to resume, what iOS has indicated so far, whether the user
  changed the transport, and whether the output was lost. Never stored on disk.
- **Held position**: the track position at the moment playback was put on hold.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-014-S1**: Every combination of the policy's inputs has one outcome, and an automated check
  covers all of them; 100% of the combinations in which any condition of AUD-014-R2 is missing end
  without a resume.
- **AUD-014-S2**: With a synthetic interruption while an imported track plays, the status reads
  "Interrupted" and the transport shows paused within 1 second; the held position is within 0.25
  seconds of the interruption point; after the end with the resume indication playback continues
  from the held position within 2 seconds.
- **AUD-014-S3**: After a resume, a hardware change and a media-services reset, 0 audio frames from
  before the restart reach the picture, and the first frame delivered is the frame at the held
  position (checked frame by frame on a test track).
- **AUD-014-S4**: Across at least 12 scripted event orders (ended before began, duplicate began,
  ended without began, during a seek, during a track change, while paused, while stopped, back to
  back, background during the interruption, reset during the interruption, after leaving the
  visualizer, after stop and restart) there is no crash, at most one playback, and the final state
  matches the policy.
- **AUD-014-S5**: Every existing automated check of Microphone and System/App Capture interruption
  behavior passes unchanged.
- **AUD-014-S6**: On a physical iPhone, a real incoming phone call during playback of an imported
  track ends with the transport state the policy prescribes (device phase; not verifiable in a
  simulator).

## Assumptions

- "Eligible in-app audio" is In-App Playback of the reference track or an imported track that the
  user started and that was playing when the interruption began.
- A phone call, an alarm, Siri and another app taking the audio all reach the app as the same
  interruption events; the policy does not tell them apart, except for the "route disconnected"
  reason.
- The app has no background audio mode (AUD-015 decides that later), so nothing plays while the
  app is in the background.
- The app listens to the interruption notice that exists on every supported iOS version (26.0 and
  later); the notices added in iOS 27 are not used by this feature (Clarifications).
- Whether and when iOS delivers the end of an interruption after a real call is observed on
  devices in the final device phase; simulator and synthetic results are not evidence for it
  (Constitution X).
- An output route indicator (AUD-007), a cross-fade between sources (AUD-012), a background
  playback policy (AUD-015), the source contract suite (QA-007) and recording recovery (REC-016)
  are later features and out of scope.
