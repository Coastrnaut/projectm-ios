# Feature Specification: REC-008 Timed recording stop

**Feature Branch**: `feature/rec-008` (spec directory `180-rec-008-timed-stop`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement REC-008 (Timed recording stop) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Stop after specified duration without blocking render thread." Acceptance,
verbatim: "Ten-second target closes file with readable index and no extra frames." P1, M, depends on REC-003
(integrated); REC-004 to REC-007, REC-015 and QA-008 are integrated too."

Identifiers carry the roadmap ID: requirements `REC-008-R1…`, success criteria `REC-008-S1…`, tasks
`REC-008-T01…`, research decisions `REC-008-D1…`.

## Baseline: what exists today (audit of 2026-11-14, commit `6b32708e`)

| Area | Today |
|---|---|
| Length limit | `RecordingSettings.maxDurationSeconds` (600 s). The frame timeline (REC-006 grid, PTS = n/fps) answers `durationReached` for a frame whose slot tick is at or beyond the limit; such a frame is never written. The frame tap then reports the stop to the main actor in a `Task` ("Recording stopped at the 10-minute limit."). |
| Finish | `MetalFrameRecorder.finish()` is async: it stops taking frames, waits for the frames in flight on the writer's serial queue (never on the frame loop) and ends the session one interval after the last appended frame. Idempotent. |
| Audio | REC-004 places host-timed chunks from the first frame's time (`RecordingAudioTimeline`); no end limit: a chunk that arrives before the finish is written in full. |
| Countdown | REC-007 counts down before the writer exists; the recording, its elapsed time and its limit start at zero when the countdown completes. |
| Disk guard | REC-015 stops with `.lowStorage` (the normal finish). |
| Validation | QA-008 `RecordingValidator` checks a finished file's duration, timestamps and frame count. |
| Settings | Recording quality, frame rate, audio, countdown. No length setting. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Which lengths? → A: Off (default), 10 seconds, 30 seconds, 1 minute and 5 minutes. No custom value: a free-form field adds input validation and accessibility work for little gain, and every length above is a whole number of seconds that every recording frame rate (24, 30, 60) divides exactly. Off keeps today's behaviour (the 10-minute limit only).
- Q: Is the length measured in wall time or media time? → A: Media time: the recording holds exactly the frames whose time is below the length (a 10 s recording at 30 fps has frames 0 … 299, at 0 … 299/30 s) and lasts exactly the length. Wall-clock stalls never make it shorter or longer.
- Q: Where is the setting? → A: Its own Settings section, "Stop recording after", directly under "Recording countdown", built like the countdown rows (buttons with a checkmark). A preference: backed up with the library settings (FILE-005), erased with the Settings category, reset by the UI-test reset.
- Q: What does the indicator show? → A: While a length is set, the elapsed time and the length: "0:07 / 0:10"; with Off it shows "0:07" as before.
- Q: How is the timed stop announced? → A: Like the other automatic stops (status row X13 on the recording lane): "Recording stopped after 10 seconds." ("… after 1 minute.", "… after 5 minutes.").

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: When frames in flight at the end are dropped (encoder not ready), is the file padded to the length? → A: No. The file ends one frame interval after the last frame actually written (never a repeated or blank frame); the drop is counted as today (REC-006 dropped slots). The acceptance runs use a writer that is not real-time limited, so no frame is dropped there.
- Q: How is an audio chunk that straddles the end handled? → A: It is cut at the exact sample of the length (441,000 samples for 10 s at 44.1 kHz); the part before is written, the rest is discarded. Nothing is added when audio ends early.
- Q: What does VoiceOver read for "0:07 / 0:10"? → A: The indicator's value reads "0:07 of 0:10"; nothing new is announced each second (only the start and the stop are announced, as today).
- Q: Is the length shown in the recorded picture or on an external display? → A: No. Like the recording indicator (REC-003-R16) it is app UI on the device screen only.
- Q: Which stop reason does the file report when the length and another stop coincide? → A: Whichever stop reaches the coordinator first wins; stops are idempotent, and the file is finished once. A timed stop is reported as its own reason (`timedStop`), distinct from the 10-minute limit (`durationReached`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Record exactly a set length (Priority: P1)

A performer sets Settings → Stop recording after to 10 seconds, taps Record, and the recording stops
by itself; the file is exactly 10 seconds long, plays, and has no frame after the 10 s mark.

**Why this priority**: It is the roadmap row and its acceptance.

**Independent Test**: Injected frames at 30 fps (and 24, 60 fps, and a jittery 60 Hz render decimated to
30 fps) into a recorder with a 10 s length; the finished file read back has duration 10 s within one
frame, exactly fps × 10 frames, no frame at or after 10 s, a readable index, and audio ending within
20 ms of 10 s.

**Acceptance Scenarios**:

1. **Given** the length is 10 s at 30 fps, **When** the recording runs past 10 s of frames, **Then** the file has exactly 300 frames (times 0 … 299/30 s), lasts 10.000 s and plays.
2. **Given** a 10 s length, **When** the stop happens, **Then** the frame loop never waits for the file to be finished; frames after the end never reach the writer.
3. **Given** a 10 s length with audio, **When** the file is finished, **Then** its audio ends within 20 ms of 10 s.
4. **Given** a 10 s length, **When** it stops, **Then** "Recording stopped after 10 seconds." is shown and announced, and the finished recording is offered as usual.

---

### User Story 2 - Other stops still win (Priority: P1)

**Independent Test**: With a 10 s length, a manual stop at 4 s and a disk-guard stop at 4 s each finish a
file of about 4 s with the usual notice (none for the manual stop, the low-storage notice for the guard).

**Acceptance Scenarios**:

1. **Given** a 10 s length, **When** the user stops at 4 s, **Then** the file holds what was recorded (about 4 s), with no timed-stop notice.
2. **Given** a 10 s length, **When** the disk guard stops at 4 s, **Then** the low-storage notice shows, not the timed-stop one.
3. **Given** a 3 s countdown and a 10 s length, **When** the countdown completes, **Then** the length counts from the recording's start (the countdown is not counted).

### Edge Cases

- The setting changed during a recording: the running recording keeps its length; the change applies to the next Record.
- Off: today's 10-minute limit and notice.
- The visual stops drawing just before the end: the 0.25 s check stops it as today (the file is shorter).
- A length is never longer than the 10-minute limit (5 minutes is the longest).
- Frames slower than the target rate: the file still ends at the length; missing slots are counted as dropped (REC-006).
- Frames in flight at the end dropped by the encoder: the file ends after the last written frame; it is never padded.
- An audio chunk straddling the end: cut at the exact sample of the length.
- The length and another stop at the same moment: the first stop to arrive wins; the file is finished once.

## Requirements *(mandatory)*

### Functional Requirements

- **REC-008-R1**: The app MUST offer a recording length with exactly these values: Off (default), 10 s, 30 s, 1 min, 5 min. Off MUST keep today's behaviour.
- **REC-008-R2**: A recording with a length MUST contain exactly the frames whose media time is below the length, and MUST end (its duration) at exactly the length when frames reached it; at 30 fps a 10 s length gives 300 frames, the last at 299/30 s.
- **REC-008-R3**: Reaching the length MUST NOT block the frame loop: the file MUST be finished asynchronously off the frame loop, and frames at or after the length MUST NOT reach the writer.
- **REC-008-R4**: Audio MUST NOT extend past the length: samples at or after it are trimmed; audio offered up to the end is kept, so it ends within 20 ms of the length.
- **REC-008-R5**: A manual stop, any automatic stop (pause, blackout, visual change, background, disk guard, writer failure) before the length MUST work as today, with its own notice.
- **REC-008-R6**: The length MUST count from the recording's first frame; a REC-007 countdown MUST NOT be counted.
- **REC-008-R7**: A timed stop MUST show and announce "Recording stopped after <length>." through the status router (row X13, recording lane), and the finished file MUST be offered as for any stop.
- **REC-008-R8**: While recording with a length, the indicator MUST read "<elapsed> / <length>" ("0:07 / 0:10"), with the accessibility value "0:07 of 0:10"; it MUST NOT appear in the recorded picture or on an external display.
- **REC-008-R9**: The setting MUST be stored on the device (key `settings.recording.timedStop`; values `off`, `10`, `30`, `60`, `300`; absent or unknown reads Off), backed up with the library settings, erased with the Settings category and reset by the UI-test reset; it MUST be in Settings as its own section with VoiceOver reading each row and its selected state.
- **REC-008-R10**: A length change during a recording MUST NOT change that recording.

### Key Entities

- **Recording length setting**: Off, 10, 30, 60 or 300 seconds; a preference.
- **Media end**: the length in the file's time base; the frame and audio limits.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **REC-008-S1**: A 10 s length at 24, 30 and 60 fps (and a jittery 60 Hz render recorded at 30 fps) yields a file of 10 s ± one frame with exactly fps × 10 frames and none at or after 10 s, read back as playable.
- **REC-008-S2**: Audio in a 10 s file ends within 20 ms of 10 s.
- **REC-008-S3**: The frame loop never waits on the finish: no frame call blocks, and finishing runs off it.
- **REC-008-S4**: A manual or disk-guard stop at 4 s of a 10 s length gives a file of about 4 s with the stop's own notice.
- **REC-008-S5**: The setting survives a relaunch, and the UI test (10 s via launch argument, record on the Photo visual, the finished file reads back at 10 s) runs in under 30 s of test time beyond the 10 s recording.

## Assumptions

- The length is not stored in scenes.
- Device evidence (a 10 s recording on D1 read back) is a `{device}` task; the acceptance is proven with injected frames on the Mac.
