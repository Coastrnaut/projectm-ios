# Feature Specification: AUD-015 Background Playback Policy

**Feature Branch**: `feature/aud-015` (spec directory `097-aud-015-background-playback-policy`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement AUD-015 (Background playback policy) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md line 102. Observable behavior, verbatim: "Document and enforce
user-visible playback behavior when app backgrounds." P1, M. Acceptance, verbatim: "Tests show
playback stops or continues only when entitled and intended; no covert capture." Verification: unit
tests plus the simulator; device testing for routes and interruptions is last."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `AUD-015-R1…`, success criteria `AUD-015-S1…`, tasks `AUD-015-T01…`. Requirements
of other features are cited by their own IDs: FR-050 (background behavior per source), FR-053
(permission re-check on return), FR-054 (lock = background), FR-055 (one-tap restart; System/App
Capture restarts only through the system picker), RI-003 (whether System/App Capture survives the
background), AUD-006-R20–R22 (user pause), AUD-014-R5, R6 (resume after an interruption),
PERF-011-R1 (presentation availability), OSC-001-R3 (no listener outside the foreground).

## Baseline: what exists today (audit of 2026-11-14, commit `c791527f`)

This is a gap row. Most of the behavior exists (T099, PERF-011, AUD-014); what is missing is one
written, user-facing policy, one decision function, a guarantee that capture never restarts while
the app is away, and a notice on return.

**Declared background modes** (`project.yml`, both the `projectM-iOS` and `CaptureLab` targets):
`UIBackgroundModes: [screen-capture]` only, added under ADR-0001 ruling 17 on 2026-11-09 after T041
on D1. `scripts/check_compliance.py` allows exactly that value and rejects every other one,
including `audio` (`BackgroundModeExceptionTests.test_other_values_and_forms_flagged`). There is no
`audio` background mode, so iOS suspends the app's audio engine shortly after it leaves the
foreground; the app cannot keep In-App Playback or the Microphone running in the background.

**Today's behavior per source** (CaptureManager.handle, LifecycleCoordinator, data-model lifecycle
matrix):

| Source | Background or lock | Return (foreground or unlock) |
|---|---|---|
| Microphone | Engine torn down (`AVMicrophoneBackend.pause`), state Paused | Resumes automatically (FR-050), after re-checking permission and input (FR-053) |
| In-App Playback | Player paused at its position, state Paused | Resumes automatically (FR-050) unless the user paused it (AUD-006) or an interruption is open (AUD-014-R5, R6) |
| System/App Capture | Untouched; the `screen-capture` mode keeps the stream while it delivers; a lock ends it (-3817), shown as "Ended by system" | Never restarted without the system picker (FR-055) |
| Visualization | Suspended in every mode: frame loop, surface and warm-up released (PERF-011) | Resumed when the app can present frames, unless the user paused it (FR-046) |

**Gaps found by the audit**:

1. **Unlock while still in the background resumes capture.** `CaptureManager` keeps one
   "presentable" flag that an unlock sets back to true even when the app is still in the background
   (the user unlocked onto the Home Screen or another app). A paused Microphone session then
   restarts its engine while the app is not visible. `LifecycleCoordinatorTests.
   testUnlockWhileStillInTheBackgroundResumesNothing` asserts that resume today. PERF-011's
   `PresentationAvailability` already treats background and lock as independent; the capture layer
   does not.
2. **A start while away is not held.** A source started while the app is in the background (a
   queued command finishing late) runs until the next lifecycle event.
3. **No notice on return.** After an automatic resume nothing tells the user that playback was
   paused or the microphone was off while they were away.
4. **Not documented** for users: the privacy policy and Help say nothing about the background.

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option, recommended option
first.

- Q: Should In-App Playback be able to keep playing in the background, with a "Keep playing in
  background" setting? → A: No, not in this feature. Continuing needs the `audio` background mode,
  which the app does not declare and the constitution's compliance check rejects; adding it is an
  App Store-facing change outside this row. In-App Playback always pauses on background or lock.
  The decision function still takes "the app declares the audio mode" and "the user asked to keep
  playing" as inputs, so that a future change is one switch, and both are false in the app; no
  setting is shown, because a setting that cannot work would mislead (AUD-015-R2, R3).
- Q: Should a return to the foreground resume the Microphone and In-App Playback automatically, or
  wait for a tap? → A: Resume automatically, as FR-050 requires (an approved feature 001
  requirement, so an existing ruling). Returning to the app is the user's action, the app is on
  screen and iOS shows its microphone indicator. AUD-014-R5, R6 and the AUD-006 user pause still
  win. What changes is that only a real return counts: the app must be in the foreground **and**
  unlocked (AUD-015-R5).
- Q: Should System/App Capture be stopped by the app on background, since nothing is drawn then?
  → A: No. It follows the system: the `screen-capture` mode (ADR-0001 ruling 17) keeps the stream
  while it delivers, iOS shows its own recording indicator the whole time, and a lock ends it,
  shown as "Ended by system". The app never restarts it without the system picker (FR-055).
  Changing this would contradict ruling 17 (AUD-015-R4).
- Q: How is the user told what happened while away? → A: A short notice under the status when
  the app returns, naming the source and what happened ("Playback paused while projectM-iOS was in
  the background." / "The microphone was off while projectM-iOS was in the background. It never
  listens in the background."). It clears itself after 8 seconds or on Dismiss, never blocks, and
  is announced to VoiceOver. "Ended by system" keeps its existing banner (AUD-015-R7).
- Q: Where is the policy documented? → A: In the privacy policy (a new "When the app is in the
  background" section, kept consistent with FILE-013's permission catalog check), in the
  feature's contract, and in an ADR, because it is a policy that later features must follow
  (AUD-015-R9).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The microphone never listens in the background (Priority: P1)

A user visualizes the room with the Microphone, then presses the Home button or locks the phone.
The app stops capturing at once and stays stopped while it is away, even if the phone is unlocked
onto another app. When the user opens the app again, capture resumes and a notice says the
microphone was off.

**Why this priority**: "No covert capture" is the acceptance criterion and a constitution value.

**Independent Test**: Start the Microphone with a fake backend that delivers frames only while its
engine runs; background, lock, unlock (still in the background): no frames reach the app and the
engine stays off; return to the foreground: it resumes and the notice shows.

**Acceptance Scenarios**:

1. **Given** the Microphone is capturing, **When** the app enters the background or the device
   locks, **Then** the engine stops and the state is Paused.
2. **Given** the app is in the background with the Microphone paused, **When** the device is
   unlocked but the app stays in the background, **Then** the engine stays off.
3. **Given** the app is in the background, **When** a Microphone start or resume is requested,
   **Then** no capture runs until the app is in the foreground and unlocked.
4. **Given** the app returns to the foreground and is unlocked, **When** permission and input still
   allow it, **Then** capture resumes within 2 seconds (FR-050) and the notice names the microphone.

### User Story 2 - In-App Playback pauses and comes back (Priority: P1)

A user plays a track as In-App Playback and switches to another app. Playback pauses at its
position; on return it continues and a notice says it paused while the app was away.

**Independent Test**: With a fake player, background then foreground: paused, then resumed, notice
shown; with "declares audio mode" and "keep playing" both true (test-only), playback continues.

**Acceptance Scenarios**:

1. **Given** In-App Playback is playing, **When** the app enters the background or locks, **Then**
   playback pauses at its position.
2. **Given** a test configuration where the app declares the audio mode and the user asked to keep
   playing, **When** the app backgrounds, **Then** playback continues and no notice is shown.
3. **Given** the user paused playback, or an interruption is open, **When** the app returns,
   **Then** playback stays as AUD-006 and AUD-014 decide.

### User Story 3 - System/App Capture follows the system (Priority: P2)

A user captures another app's audio and leaves the app. The capture continues while iOS lets it
(its recording indicator stays visible); a lock ends it and the app shows "Ended by system" with a
one-tap restart that re-presents the picker.

**Acceptance Scenarios**:

1. **Given** System/App Capture is delivering, **When** the app backgrounds, **Then** the app does
   not stop or pause it.
2. **Given** the system ended the capture while the app was away, **When** the user returns,
   **Then** "Ended by system" shows and nothing restarts without the picker.

### User Story 4 - Rendering stops while away (Priority: P2)

Whatever the source, the visualization draws nothing while the app is in the background or locked,
and resumes on return unless the user paused it.

**Acceptance Scenarios**:

1. **Given** any source, **When** the app backgrounds or locks, **Then** the visualization and
   every presentation-bound resource are suspended.

### Edge Cases

- Lock while the app is in the foreground (iOS sends both background and lock): handled once.
- Unlock arrives before "will enter foreground": only the foreground resumes.
- Foreground without an unlock event: entering the foreground proves the device is unlocked
  (PERF-011-R1).
- Background while a start is in flight (permission prompt, picker): the start is held as Paused
  for Microphone and In-App Playback once it completes.
- The notice must not appear when nothing was paused (System/App Capture, no session, a session
  the user had already paused).
- A new start, Stop, a user pause or resume clears the notice.

## Requirements *(mandatory)*

### Functional Requirements

- **AUD-015-R1**: The app MUST decide what happens to the active source when it leaves or returns
  to the foreground through one policy that takes the source, whether the app is in the
  background, whether the device is locked, whether the app declares the audio background mode and
  whether the user asked to keep playing, and returns an action (run, pause playback, stop capture,
  continue playback, follow the system) and a user-visible reason.
- **AUD-015-R2**: In-App Playback MUST pause on background or lock, unless the app declares the
  audio background mode **and** the user asked to keep playing; only then may it continue.
- **AUD-015-R3**: The app as shipped MUST NOT declare the audio background mode and MUST NOT offer
  a "keep playing" setting (Clarifications); the policy's continue path is reachable only in tests.
- **AUD-015-R4**: System/App Capture MUST follow the system in the background: the app neither
  stops nor pauses it, an end by the system shows "Ended by system", and it is never restarted
  without the system picker (FR-055).
- **AUD-015-R5**: Microphone capture MUST stop on background or lock, whatever the background
  modes, and MUST NOT run again until the app is both in the foreground and unlocked. An unlock
  while the app is still in the background resumes nothing.
- **AUD-015-R6**: A Microphone or In-App Playback start or resume that completes while the app is
  away MUST be held Paused (no capture, no playback) until the next real return.
- **AUD-015-R7**: On a real return after the app paused playback or stopped the microphone, the
  app MUST show a non-blocking notice naming the source and what happened, announced to VoiceOver,
  that clears after 8 seconds, on Dismiss, or on the next start, Stop, pause or resume.
- **AUD-015-R8**: The visualization and every presentation-bound resource MUST be suspended while
  the app is in the background or locked, in every source mode (PERF-011, FR-050).
- **AUD-015-R9**: The policy MUST be documented for users in the privacy policy and for developers
  in the feature contract and an ADR; the permission catalog check must keep passing.
- **AUD-015-R10**: Automatic resume on return keeps FR-050, FR-053, AUD-006-R22 and AUD-014-R5, R6
  unchanged.

### Key Entities

- **Background context**: source, in background, locked, declares audio mode, keep playing.
- **Background decision**: action plus reason; the reason carries the notice text, if any.
- **Background notice**: the reason shown on return; cleared by time, Dismiss or a user command.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-015-S1**: A table test covers every source × (foreground, background, locked, background
  and locked) × (keep playing off/on) × (audio mode declared or not) and matches the policy table
  in the contract: 3 × 4 × 2 × 2 = 48 cases, all passing.
- **AUD-015-S2**: With a fake microphone backend, zero frames reach the app after background,
  through lock and an unlock in the background, and frames flow again after the real return.
- **AUD-015-S3**: In-App Playback pauses (shipped configuration) or continues (test configuration)
  as the policy says, in a test with the fake player.
- **AUD-015-S4**: After background and return, the status reads the resumed state and the notice
  names the source, in a UI test under 30 seconds.
- **AUD-015-S5**: No capture source restarts while the app is away in any tested sequence.
- **AUD-015-S6**: On D1, per source, lock, background and return behave as the contract says
  (device task, open until run).

## Assumptions

- `UIBackgroundModes` stays `[screen-capture]` (ADR-0001 ruling 17); adding `audio` is a separate,
  owner-visible decision.
- iOS delivers "did enter background" on a lock; the protected-data notifications mark lock and
  unlock only with a passcode set, so the foreground event is the reliable return signal.
- Simulator results are never evidence for capture behavior; the device task stays open.
