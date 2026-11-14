# Feature Specification: REC-007 Recording countdown

**Feature Branch**: `feature/rec-007` (spec directory `175-rec-007-countdown`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement REC-007 (Recording countdown) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Start after a configurable countdown with cancellation." Acceptance,
verbatim: "Cancel prevents file creation; completed countdown starts once." P1, S, depends on REC-003
(integrated); REC-004, REC-005, REC-006 and REC-015 are integrated too."

Identifiers carry the roadmap ID: requirements `REC-007-R1…`, success criteria `REC-007-S1…`, tasks
`REC-007-T01…`, research decisions `REC-007-D1…`.

## Baseline: what exists today (audit of 2026-11-14, commit `5aaeebe5`)

| Area | Today |
|---|---|
| Start | Record (`ControlsOverlay`, item `record`) calls the recording coordinator's toggle: idle → start at once, recording → stop, finishing → "busy" refusal. The start checks the refusals (no visual, projectM, blacked out, paused, busy, offered result), resolves profile and rate (REC-005, REC-006), reads free storage once (REC-015), then creates the file's writer and attaches the frame tap. |
| Other start paths | None. OSC and MIDI (including MIDI-008 transport) never start or stop a recording; only the Record control does. |
| States | idle, recording, finishing. The recording indicator shows while not idle; the state's changes post status rows X9 ("Recording started"), X10, X11 on the `recording` announcer lane. |
| Stops | A 0.25 s check stops on pause, blackout, a changed or lost visual, a stopped frame loop; going to the background stops inside a background-task grant. |
| Settings | Recording quality (REC-005), Recording frame rate (REC-006), Recording audio (REC-004). No countdown. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Which countdown lengths? → A: Off, 3 s, 5 s and 10 s; Off is the default, so a user who never opens the setting records exactly as before (immediate start).
- Q: Where is the setting? → A: Its own Settings section, "Recording countdown", directly under "Recording frame rate", four rows built like the frame-rate rows (buttons with a checkmark). It is a preference, not a device capability: it is backed up with the library settings (FILE-005), erased with the Settings category and reset by the UI-test reset.
- Q: When are the refusals checked? → A: Before the countdown starts (so a countdown never runs only to be refused) and again when it completes (anything may have changed); a refusal at completion shows its usual notice and leaves the state idle.
- Q: How is a countdown cancelled? → A: By tapping Record again (it reads "Cancel countdown" while counting), by the on-screen Cancel button, or by Escape on a hardware keyboard. Leaving the visualizer, going to the background, the shown visual changing or being lost, the output being blacked out and Pause also cancel it.
- Q: What does "starts once" mean for a tap at the last instant? → A: A Record tap in the last 0.25 s of the countdown or in the first 0.5 s of the recording it started is ignored: it neither cancels, starts a second recording nor stops the one just started. The Cancel button and Escape are explicit and still cancel up to completion.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Is the countdown number shown in the recording or on an external display? → A: No. It is app UI on the device screen only, like the recording indicator (REC-003-R16); the recorded picture and the external output never show it.
- Q: How is a cancellation shown? → A: As a transient status caption (4 s, ACC-011-R7) and an announcement on the recording lane: "Countdown cancelled" for the user's own cancel, "Countdown cancelled: <reason>." for an automatic one (for example "Countdown cancelled: the app went to the background."). No persistent notice: nothing needs the user's action.
- Q: Does the countdown stay visible when the controls hide? → A: Yes. The number and its Cancel button sit with the recording indicator, which never hides; the controls keep their own auto-hide.
- Q: Does the countdown count toward the 10-minute limit or the recording's elapsed time? → A: No. The recording, its elapsed time and its limit start at zero when the countdown completes.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Start a recording after a countdown (Priority: P1)

A performer sets Settings → Recording countdown to 3 s, taps Record, sees and hears "3, 2, 1", puts
the phone down, and the recording starts when the count reaches zero.

**Why this priority**: It is the roadmap row: start after a configurable countdown.

**Independent Test**: With an injected clock, a 3 s countdown counts 3 → 2 → 1 and starts exactly one
recording at 3.0 s; a second Record tap at 2.99 s or at 3.0 s starts no second recording and no stop.

**Acceptance Scenarios**:

1. **Given** the countdown is 3 s, **When** the user taps Record, **Then** the state is counting down from 3, the number shows on screen and is announced, and no file or writer exists yet.
2. **Given** a 3 s countdown, **When** 3 s pass, **Then** exactly one recording starts.
3. **Given** a 3 s countdown, **When** the user taps Record again at 2.99 s or 3.0 s, **Then** exactly one recording starts and keeps running.
4. **Given** the countdown is Off, **When** the user taps Record, **Then** the recording starts at once (today's behaviour).

---

### User Story 2 - Cancel a countdown (Priority: P1)

The performer changes their mind: tapping Record again, Cancel or Escape stops the countdown and no
file is made.

**Why this priority**: The acceptance names "Cancel prevents file creation".

**Independent Test**: A 3 s countdown cancelled at 1.5 s: zero writer creations, no file in the
recordings folder, state idle; advancing the clock past 3 s still starts nothing.

**Acceptance Scenarios**:

1. **Given** a 3 s countdown, **When** the user cancels at 1.5 s, **Then** the state returns to idle, no writer was created, no file exists, "Countdown cancelled" is shown and announced, and nothing starts later.
2. **Given** a countdown, **When** the app goes to the background, the visualizer is left, or the shown visual is lost, **Then** the countdown is cancelled the same way, with the reason.

### Edge Cases

- A refusal (projectM shown, paused, blacked out, offered result, busy) at the Record tap: refused at once, no countdown.
- A refusal at completion (for example low storage): the usual notice; state idle; no writer.
- The setting changed during a countdown: the running countdown keeps its length; the change applies to the next Record.
- VoiceOver: each second is announced on the recording lane ("Recording in 3", "2", "1"), then "Recording started".
- Reduce Motion, and always: the number changes without any animation (no pulsing, no scaling).
- The controls auto-hide during a countdown: the number and Cancel stay visible.
- An external display or the recorded picture never shows the countdown.

## Requirements *(mandatory)*

### Functional Requirements

- **REC-007-R1**: The app MUST offer a recording countdown with exactly these values: Off (default), 3 s, 5 s, 10 s. Off MUST start a recording at the Record tap as before.
- **REC-007-R2**: With a countdown, Record MUST first apply the existing start refusals; when none applies it MUST enter a counting-down state with the remaining whole seconds, and MUST NOT create a file or a writer, arm the audio tap or read storage until the countdown completes.
- **REC-007-R3**: The remaining seconds MUST decrease by one each second from the countdown's own start time (no drift), and at zero exactly one recording MUST start through the normal start path (all refusals, profile, rate, storage checks applied again); its elapsed time and 10-minute limit start at zero then.
- **REC-007-R4**: Tapping Record during a countdown, the countdown's Cancel button and Escape MUST cancel it; a Record tap in the last 0.25 s of the countdown or the first 0.5 s of the recording it started MUST be ignored.
- **REC-007-R5**: Going to the background, leaving the visualizer, the shown visual changing or being lost, a stopped frame loop, a blackout and Pause MUST cancel a countdown.
- **REC-007-R6**: A cancelled countdown MUST leave the state idle, no file, no writer and nothing scheduled; it MUST show a transient caption and announce "Countdown cancelled" (user) or "Countdown cancelled: <reason>." (automatic).
- **REC-007-R7**: While counting, the visualizer MUST show the remaining number as an accessible element ("Recording in 3") with a Cancel button, the Record control MUST read "Cancel countdown", and each second MUST be announced through the status router on the recording lane. Nothing MUST animate. The number and Cancel MUST stay visible while the controls are hidden and MUST NOT appear in the recorded picture or on an external display.
- **REC-007-R8**: The setting MUST be stored on the device (key `settings.recording.countdown`; values `off`, `3`, `5`, `10`; absent or unknown reads as Off), backed up with the library settings, erased with the Settings category and reset by the UI-test reset.
- **REC-007-R9**: The setting MUST be in Settings as its own "Recording countdown" section under "Recording frame rate"; VoiceOver MUST read each row and its selected state.
- **REC-007-R10**: Only the Record control starts a countdown; no other trigger (OSC, MIDI, transport) starts, completes or cancels one except the automatic cancellations of R5.

### Key Entities

- **Countdown setting**: Off, 3, 5 or 10 seconds; a preference.
- **Countdown**: its start time, length, remaining seconds and a token that makes its completion run at most once.
- **Cancellation**: who or what cancelled it (user, background, visualizer left, visual lost, blackout, pause).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **REC-007-S1**: A 3 s countdown cancelled at 1.5 s creates 0 writers and 0 files, and the state is idle.
- **REC-007-S2**: A completed 3 s countdown starts exactly 1 recording; a second Record tap at 2.99 s or 3.0 s adds 0 recordings and 0 stops.
- **REC-007-S3**: With the countdown Off, Record starts the recording in the same tap.
- **REC-007-S4**: Backgrounding during a countdown cancels it with 0 writers.
- **REC-007-S5**: The announcements of a 3 s countdown are, in order, "Recording in 3", "2", "1", "Recording started".
- **REC-007-S6**: The UI test (countdown 3 s, Record, countdown visible, Cancel, no recording indicator) runs in under 30 s.

## Assumptions

- The countdown is a convenience for the person recording; it needs no device evidence beyond the simulator UI test and the unit tests (a device check is listed as a `{device}` task).
- Sound cues (beeps) are out of scope: the app's audio is the visual's input, and a beep would be captured by the microphone.
- The countdown is not stored in scenes.
