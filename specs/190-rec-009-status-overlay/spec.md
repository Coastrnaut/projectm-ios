# Feature Specification: REC-009 Recording status overlay

**Feature Branch**: `feature/rec-009` (spec directory `190-rec-009-status-overlay`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement REC-009 (Recording status overlay) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Show active duration, dropped frames and storage warnings only in UI." Acceptance,
verbatim: "Export does not accidentally include control overlay unless opted in." P1, M, depends on REC-003
(integrated); REC-006 (dropped frames), REC-007 (countdown), REC-008 ("0:07 / 0:10") and REC-015 (disk guard) are
integrated too."

Identifiers carry the roadmap ID: requirements `REC-009-R1…`, success criteria `REC-009-S1…`, tasks
`REC-009-T01…`, research decisions `REC-009-D1…`.

## Baseline: what exists today (audit of 2026-11-14, commit `f80ed10c`)

| Area | Today |
|---|---|
| What a recording holds | Every recordable visual (Camera, Photo, Video, Text: the compositor; the native spectra: their own drawable) feeds `VideoRecordingTap.record` inside its own frame's command buffer. The compositor's `encodeOutput` draws the frame's composite texture (after the FX-019 flash guard and FX-003 grade) into the recorder's pixel buffer; the spectra blit their Metal drawable. SwiftUI views are separate Core Animation layers above the Metal layer and are never drawn into either texture. |
| External display | OUT-001/OUT-002: the visual's own view moves to the external screen; the device keeps the controls, the indicator and the "Showing on external display" note. The recording is still fed from the visual's own frame loop. |
| Duration | REC-003 indicator "REC 0:07" (REC-008: "0:07 / 0:10" with a length) in the visualizer's banner stack, with or without the controls. |
| Dropped frames | REC-006 counts `RecordingStatistics.droppedSlots` live in the recorder and stores `RecordedVideo.droppedFrames` after the finish (Settings shows the last recording's). Nothing shows it during a recording. |
| Storage | REC-015 reads the free storage once at Record and every 5 s while recording, only to refuse or stop (`.lowStorage`). The value is never shown. |
| Announcements | ACC-011 status router (recording lane, ACC-004 gate: 1 s window, identical text dropped within 2 s). |
| Burn-in | No option exists to draw any app UI into a recording. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Is an "Include overlay in recording" option offered? → A: No. The overlay is never recorded and there is no opt-in: burning app UI into a file adds a text-rendering compositor pass, a setting, scene and backup fields and a privacy surface (free storage in a shared file) for little value. The acceptance ("does not accidentally include the control overlay unless opted in") holds because no path draws app UI into a recording; a test proves it on the real recording path. A later feature may add an explicit opt-in as a compositor text layer, never by screen capture.
- Q: What does the overlay show? → A: Under the existing indicator ("REC 0:07" / "0:07 / 0:10", the duration), one compact line for dropped frames ("Dropped frames: 3") and one for storage ("2.1 GB free, about 14 min left"), only while recording (not while counting down or finishing).
- Q: When is the dropped-frames line a warning? → A: When at least 10 slots were dropped and they are at least 2% of the recording's slots (written + dropped). It then reads "Dropping frames: 12 (3%)" with a warning symbol. Below that it is a plain count.
- Q: How is "min left" computed and when is storage a warning? → A: Minutes until the REC-015 guard would stop the recording: (free − the guard's stop threshold) ÷ the larger of the estimated and measured byte rate, rounded down. Under 5 minutes is "low" (warning symbol), under 1 minute is "critical" ("under 1 min left"). Unknown free storage reads "Free storage unknown" and never warns.
- Q: Are warnings announced? → A: Yes, through the status router on the recording lane, only when a warning level rises (dropped: none → warning; storage: ok → low → critical), at most once per kind every 30 s of recording; never the plain counts. They are system rows, so they are dropped while the app is not active (ACC-011-R10).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See how the recording is going (Priority: P1)

A performer records a set. Under the recording indicator they see the elapsed time, how many frames
were dropped and how much storage is left, and are warned (on screen and by VoiceOver) when frames
drop heavily or storage runs low.

**Why this priority**: It is the roadmap row.

**Independent Test**: A UI test starts a recording on the Photo visual and finds the indicator's duration,
the dropped-frames line and the storage line; unit tests drive the summary with set statistics and
storage readings.

**Acceptance Scenarios**:

1. **Given** a recording is running, **When** the overlay shows, **Then** it reads the duration, "Dropped frames: N" from the recorder's statistics and "X GB free, about M min left".
2. **Given** 12 of 400 slots dropped, **When** the overlay updates, **Then** the dropped line is a warning and the warning is announced once.
3. **Given** free storage falls to 4 minutes of recording, **When** the 5 s storage reading arrives, **Then** the storage line is "low" and announced once; below 1 minute it is "critical" and announced again.
4. **Given** the warnings stay, **When** later readings arrive, **Then** nothing more is announced for 30 s of recording per kind, and never for the same level twice.

---

### User Story 2 - The recording never shows the app's controls (Priority: P1)

A performer records with the controls and the status overlay on screen. The finished file holds only
the visual.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: A solid-colour Photo visual is recorded through the app's real recording path while a
probe overlay (a distinctive colour and text) and the real status overlay sit on top of it in the same
window; every frame read back is the visual's colour, uniform within tolerance, with no probe pixel. A
window snapshot taken during the recording shows the probe (it really was on screen).

**Acceptance Scenarios**:

1. **Given** the overlay is on screen, **When** the recording is read back, **Then** no frame contains the overlay's pixels.
2. **Given** the visual is on an external display, **When** recording, **Then** the file holds the visual only (the controls are on the device screen; the recording is fed from the visual's frame loop).

### Edge Cases

- Countdown (REC-007): the overlay is hidden; it starts at the recording's start with 0 dropped.
- Finishing: the overlay is hidden; the indicator shows "Finishing".
- Unknown free storage (a failed reading): "Free storage unknown", no warning.
- Free storage below the stop threshold before the guard acts: "under 1 min left", critical.
- A frame rate drop that fills no slots (render faster than recording): no drops.
- Accessibility sizes: the lines wrap; VoiceOver reads each line as one element with its warning.
- Reduce Motion: the overlay never animates (no pulsing); warnings are shown by symbol and text, not by motion or colour alone.

## Requirements *(mandatory)*

### Functional Requirements

- **REC-009-R1**: While a recording runs, the visualizer MUST show, with the existing indicator's duration, a dropped-frames line and a storage line, with or without the controls, only on the device screen.
- **REC-009-R2**: The dropped-frames line MUST show the recorder's live dropped slots (REC-006), refreshed at least every 0.25 s; it MUST be a warning when dropped ≥ 10 and dropped ≥ 2% of written + dropped slots.
- **REC-009-R3**: The storage line MUST show the free storage (decimal GB with one decimal from 1 GB, else whole MB) and the minutes until the disk guard would stop the recording, from the REC-015 readings (at start and every 5 s); low under 5 minutes, critical under 1 minute; unknown free storage reads "Free storage unknown".
- **REC-009-R4**: Warnings MUST be announced through the status router (recording lane, system cause) only when their level rises, at most once per kind per 30 s of recorded time.
- **REC-009-R5**: The overlay MUST NOT animate; a warning MUST carry a symbol and words (not colour alone); VoiceOver MUST read each line, including "warning".
- **REC-009-R6**: No app UI (controls, indicator, status overlay, notices) MUST ever be drawn into a recording; there is no option to include it.
- **REC-009-R7**: The free storage and dropped counts MUST stay in memory only (never stored, logged or sent).

### Key Entities

- **Recording status summary**: duration, dropped slots and their warning, free storage, minutes left and its level.
- **Warning announcement throttle**: per kind, the last announced level and the recorded time of the last announcement.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **REC-009-S1**: A recording made through the app's real recording path with the overlay and a probe on screen contains zero probe-coloured pixels in every frame, and every frame is the visual's colour within tolerance.
- **REC-009-S2**: The dropped-frames line equals the recorder's dropped-slot count; the warning switches exactly at the threshold.
- **REC-009-S3**: Storage levels switch exactly at 5 and 1 minutes; unknown storage never warns.
- **REC-009-S4**: A burst of rising and falling readings yields at most one announcement per kind per 30 s of recording.
- **REC-009-S5**: The UI test (start a recording, read the duration and storage lines) runs in under 30 s.

## Assumptions

- The overlay is not a setting and adds no stored keys, scene fields or backup items.
- Device evidence (overlay on D1 during a real recording) is a `{device}` task; simulator results are not evidence.
