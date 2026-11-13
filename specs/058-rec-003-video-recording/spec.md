# Feature Specification: REC-003 Video Recording

**Feature Branch**: `feature/rec-003` (spec directory `058-rec-003-video-recording`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (REC-003-T01-T22 verified on the Mac: host, Linux shape and iOS 27.2 simulator; T23-T25 `{device}` open)

**Input**: User description: "Implement REC-003 (Video recording) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Record composited frames into local
video file with timestamped frames." Acceptance, verbatim: "Ten-second fixture decodes and preserves
monotonic timestamps." P0, effort XL, depends on CMP-001 (integrated). Verification: fixture encoding +
simulator + device LAST stage. Video only: no audio track in this row (REC-004 owns audio and its
legality rules). REC-005 to REC-016 (quality profiles, frame rate choice, countdown, timed stop,
status overlay, library, Photos, share sheet, offline export, aspect presets, disk guard, interruption
recovery) must be able to build on it."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `REC-003-R1…`, success criteria `REC-003-S1…`, tasks `REC-003-T01…`. Requirements
of other features are cited by their own IDs: CMP-001 (compositor, ADR-0013), REC-001 (still frame
capture, `specs/055-rec-001-still-frame-capture`), FX-019 (composite flash guard), FR-072 (Reduce
flashing), FR-085 (Paused), FR-065 (what the app may store), FR-070 (accessibility), OUT-001
(external display), OUT-010 (output blackout), PERF-011 (presentation loss), CAM-001 (Camera visual),
MED-001 / MED-002 / MED-009 (Photo, Video, Text visuals), VIS-001 / VIS-002 (native spectra).

## Baseline: what exists today (audit of 2026-11-13, commit `4254e58`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Recording | REC-001 saves one frame as PNG or HEIF through Files. No video writer anywhere in the app or packages. | No video recording. |
| Compositor visuals (Camera, Photo, Video, Text) | CMP-001 composite, flash guard, output pass into a display-only drawable; REC-001 can capture one frame. | No continuous per-frame output. |
| Native spectra (Circular, Linear) | Draw into the drawable; REC-001 reads one drawable back. | No continuous per-frame output. |
| projectM (ANGLE) | Draws through GL into the window surface; REC-001 reads one frame with a GL read-back. | No continuous output; a per-frame GL read-back stalls the GPU. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Should projectM (the ANGLE visual) be recordable in this row, given its only frame path today is a CPU read-back that stalls the GPU? → A: No. Record covers the compositor visuals (Camera, Photo, Video, Text) and the native spectra (Circular, Linear), whose frames can be copied on the GPU into the encoder's buffers without a CPU read-back; for projectM, Record is shown unavailable with a reason. A per-frame GL read-back would cut the frame rate of the app's main visual unmeasured (Constitution X), and a GPU-side path out of ANGLE's surface is a separate piece of work (ADR follow-up). Rejected: per-frame read-back at a reduced rate (an unmeasured stall on the main visual, and a jerky video); waiting with the whole row until projectM is solved (blocks REC-004 to REC-016).
- Q: When the user pauses or blacks out the output during a recording, should the recording pause (and resume later in the same file) or stop and finish the file? → A: Stop and finish the file, keep what was recorded and offer it, with a notice. One rule for every interruption (pause, blackout, background, visual or size change, presentation loss) is predictable, never records what the user chose to hide, and leaves no half-open file across long gaps. Resuming in the same file needs timeline offsets and a held writer; REC-016 (interruption recovery) can add it. Rejected: pause and resume in one file (more state; a blackout could silently resume recording); discard the recording (loses the user's work).
- Q: What frame rate, codec and size should the video have, before REC-005 (quality profiles) and REC-006 (frame rate choice) exist? → A: At most 30 frames per second with each frame's real presentation time (frames closer than the interval are skipped), HEVC when the device can encode it and H.264 otherwise, the drawable's pixel size cropped to even dimensions and scaled down to fit 1920 pixels on the long side, 8-bit SDR tagged Rec. 709. 30 fps halves the encoder's load against a 60 Hz loop and matches the visuals' usual rate under the quality governor; a 1080p-class cap keeps files and thermal load moderate on every device including the A16 iPad; HEVC halves file size where supported. Rejected: 60 fps (twice the load, unmeasured on devices); the full drawable size (2752 px on iPad Pro; heavier encoding and files); a constant frame rate with duplicated frames (invents frames the screen never showed).
- Q: What happens to a recording when the app goes to the background? → A: The recording stops at once and the file is finished while the app still runs (with a short background-task grant from the system); the Files sheet is offered when the app returns to the foreground. The visuals stop drawing in the background anyway, and an unfinished file is unreadable. Rejected: keep the writer open across the background (the system may suspend or end the app with an unreadable file); discard the recording (loses the user's work).
- Q: Should Record check free storage before starting? → A: No storage estimate in this row: the disk-space query is a required-reason API (privacy manifest) and REC-015 (recording disk guard) owns estimates and low-space stops. A writer failure (including a full disk) stops the recording, deletes the partial file and shows "The recording couldn't be finished." The 10-minute cap bounds a file to about 0.5-1 GB at the chosen size. Rejected: query free space now (a new required-reason declaration without the row that needs it); no cap (an unbounded file).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Record the visual to a video file (Priority: P1)

A user likes what a visual is doing and wants to keep it. They tap Record in the visualizer's
controls; a recording indicator with the elapsed time appears. When they tap Stop recording, the
video is finished and the system's Files sheet opens with the video file; they choose where to save
it.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: An app UI test with a DEBUG option that replaces the Files sheet with a
temporary folder: tap Record on a compositor visual, see the indicator, stop after about 2 s; a
probe reports the file's duration, frame count, codec and the absence of an audio track.

**Acceptance Scenarios**:

1. **Given** a recordable visual is running, **When** the user taps Record, **Then** recording starts
   with the next shown frame and an indicator shows "Recording" and the elapsed time.
2. **Given** a recording runs, **When** the user taps Stop recording, **Then** the file is finished
   without stopping or slowing the visual, and the Files sheet offers it.
3. **Given** the Files sheet is open, **When** the user cancels it, **Then** nothing is saved and the
   app deletes its temporary file.
4. **Given** the visual is projectM, **When** the user opens the controls, **Then** Record is shown
   as unavailable and says why (recording covers the Camera, Photo, Video, Text and spectrum visuals
   in this release).

---

### User Story 2 - The file plays back with correct, increasing timestamps (Priority: P1)

The recorded file opens in any player; every frame has a presentation time later than the one
before; the file's duration matches the recorded time; the picture is what the screen showed (after
the flash limiter), with no audio track.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: Fixture encoding: a 10-second recording of a 160 × 120 compositor source driven
by a simulated frame clock at 30 frames per second, each frame drawing its index as a pattern, is
decoded: every frame's time is strictly later than the previous one and equals the time written; the
frame count and duration match; the decoded indices increase.

**Acceptance Scenarios**:

1. **Given** the 10-second fixture, **When** it is decoded, **Then** 300 frames ± 1 come back, each
   presentation time strictly greater than the previous and equal to the written one, and the
   duration is 10 s ± one frame.
2. **Given** the same file, **When** each frame's pattern is read, **Then** the indices increase from
   0 in order with none repeated.
3. **Given** a frame whose time is not later than the previous written frame, **When** it arrives,
   **Then** it is dropped and counted, never written.
4. **Given** any recording, **When** its tracks are listed, **Then** it has exactly one video track
   and no audio track, and no location or device metadata.

---

### User Story 3 - Recording never stalls the show (Priority: P1)

Recording runs beside the visual: when the device cannot encode fast enough, frames are left out of
the file (and counted) instead of slowing the picture, and memory use stays bounded.

**Why this priority**: The visualizer is used live (external display, OUT-001); a recorder that
blocks the frame loop would ruin the show.

**Independent Test**: With an encoder that is held stalled, the frame loop keeps submitting frames:
at most the fixed number of frames is waiting, the rest are counted as dropped, and no submission
waits.

**Acceptance Scenarios**:

1. **Given** the encoder is stalled, **When** frames keep coming, **Then** at most N (3) frames are
   in flight and every further frame is dropped and counted.
2. **Given** the encoder catches up, **When** frames come, **Then** they are written again.

---

### User Story 4 - Interruptions end the recording safely (Priority: P2)

When the app goes to the background, the user pauses, the output is blacked out, the visual changes,
the picture size changes, presentation is lost or the maximum length is reached, the recording stops
and is finished; what was recorded is kept and offered, with a notice saying why it stopped.

**Why this priority**: A recording must never be left unreadable, and must not record what the user
chose to hide.

**Independent Test**: Coordinator tests with a fake recorder and lifecycle: each event stops the
recording with its reason and finishes the file; a fixture recording stopped by a simulated
background event decodes.

**Acceptance Scenarios**:

1. **Given** a recording runs, **When** the app goes to the background, **Then** the file is finished
   before the app is suspended where the system allows, and offered when the app returns.
2. **Given** a recording runs, **When** the user pauses or blacks out the output, **Then** recording
   stops and the file is offered with a notice.
3. **Given** the output is blacked out or the user paused, **When** the user taps Record, **Then**
   recording does not start and a notice says why.
4. **Given** a recording reaches 10 minutes, **Then** it stops by itself and the file is offered.

### Edge Cases

- The writer fails (storage full, encoder error): recording stops, the partial file is deleted, a
  notice says "The recording couldn't be finished." No free-space estimate is made (REC-015).
- Fewer than 2 frames were written before stop: no file is offered; a notice says nothing was
  recorded.
- The drawable has an odd width or height: the recording drops the last pixel column or row so the
  video's size is even.
- The drawable is larger than the recording size cap: the video is scaled down to fit, keeping the
  aspect ratio.
- The device rotates or the visual moves to or from the external display mid-recording (picture size
  changes): the recording stops and is finished.
- Save Frame during a recording: allowed (REC-001 rules); it does not disturb the recording.
- A second Record tap while finishing: ignored until the file is ready.
- Leftover temporary recordings from a crash: deleted at the next launch.
- VoiceOver: Record, Stop recording and the indicator have labels; start, stop and failures are
  announced as notices.

## Requirements *(mandatory)*

### Functional Requirements

- **REC-003-R1**: The visualizer's controls MUST offer Record for the Camera, Photo, Video, Text,
  Circular Spectrum and Linear Spectrum visuals. For projectM, Record MUST be shown unavailable with
  its reason.
- **REC-003-R2**: Recording MUST start only on the user's explicit Record action and stop on Stop
  recording or one of the stop events (R11); nothing is recorded otherwise.
- **REC-003-R3**: Each recorded frame MUST be the frame the visual presents, as shown: after the flash
  limiter or composite flash guard (FX-019) and any glow, at the drawable's pixel size (cropped to even
  dimensions), scaled down to fit the size cap (R6) when larger.
- **REC-003-R4**: Recording MUST NOT change the frame shown, the visual's state, the flash history or
  the audio, and MUST NOT make the frame loop wait for the encoder.
- **REC-003-R5**: Frame times MUST come from the visual's frame clock (the time each frame is
  presented), measured from the first recorded frame, on a fixed 1/600 s time base. A frame whose
  time is not strictly later than the last written frame's MUST be dropped and counted.
- **REC-003-R6**: The video MUST be at most 30 frames per second (frames closer than the frame
  interval are skipped, not counted as drops), HEVC when the device can encode it and H.264
  otherwise, with the long side at most 1920 pixels, 8-bit, standard dynamic range, tagged with
  Rec. 709 color.
- **REC-003-R7**: At most 3 frames MAY be waiting for the encoder; when 3 are waiting, or the encoder
  is not ready, the new frame MUST be dropped and counted. Memory for recording MUST stay bounded by
  those frames.
- **REC-003-R8**: The file MUST have exactly one video track and no audio track (REC-004 owns audio),
  and no metadata beyond what the container requires: no location, device, user or app identifiers.
- **REC-003-R9**: Finishing the file MUST run off the main thread; the main thread only starts and
  stops the recording and receives the result.
- **REC-003-R10**: The result MUST be typed: file location, pixel size, codec, frame count, duration
  and dropped-frame counts; or a typed failure with a user-visible reason.
- **REC-003-R11**: Recording MUST stop and finish the file, keeping what was recorded, when: the user
  stops it; it reaches 10 minutes; the app goes to the background; the user pauses (FR-085); the
  output is blacked out (OUT-010); the visual changes; the picture size changes; presentation is lost
  (PERF-011). A notice MUST name the reason for every stop except the user's own.
- **REC-003-R12**: Record MUST refuse with a notice while the output is blacked out or restoring
  ("Restore the output to record"), while paused ("Resume to record"), and for projectM.
- **REC-003-R13**: The finished file MUST be handed to the system Files exporter; the user chooses
  the location. The app MUST NOT write to the photo library in this row, and MUST delete its
  temporary file when the exporter finishes or is cancelled, and any leftover temporary recordings at
  launch.
- **REC-003-R14**: The timestamp, frame-rate, size and bounded-queue rules MUST be testable without a
  device or the simulator, and build on Linux; the encoding acceptance runs on the Mac host.
- **REC-003-R15**: Only public, documented platform APIs (Constitution I); no new Metal shader source;
  no networking; no new permission or usage description; no required-reason API without a
  declaration; builds for iOS 26 and 27.
- **REC-003-R16**: Record, Stop recording, the indicator and the notices MUST have accessibility
  labels (FR-070); the indicator is app UI and is never part of the recorded picture.
- **REC-003-R17**: A writer failure MUST stop the recording, release its resources, delete the
  partial file and show a notice.

### Key Entities

- **Recording settings**: frame rate cap, long-side cap, codec preference, maximum duration, frames
  in flight.
- **Recording timeline**: the first frame's time, the last written frame's time, the frame interval.
- **Recording statistics**: frames written, dropped (encoder busy), dropped (time not increasing),
  skipped (frame rate cap).
- **Recorded video**: file location, width, height, codec, frame count, duration, statistics.
- **Stop reason**: user, maximum duration, background, paused, blacked out, visual changed, size
  changed, presentation lost, writer failed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **REC-003-S1**: The 10-second fixture decodes with 300 ± 1 frames, strictly increasing frame times
  equal to the written ones, duration 10 s ± one frame interval, increasing decoded indices, one video
  track, no audio track (100% of runs).
- **REC-003-S2**: With a stalled encoder, frames waiting never exceed 3 and every other frame is
  counted as dropped, with no submission waiting.
- **REC-003-S3**: Non-increasing frame times are never written (unit tests on the timeline rule).
- **REC-003-S4**: Every stop event in R11 finishes a readable file in coordinator tests.
- **REC-003-S5**: The app UI test records about 2 s on a compositor visual and reads back a file with
  frames, a video codec and no audio track, in under 30 s.
- **REC-003-S6**: On D1 and D3 (iPadOS 26.5), 60-second recordings at the device's drawable size and
  on a 4K external display report frame rate, dropped frames and thermal state, and play in Files
  (device stage, owner's hands).

## Privacy Review

- Data: a video of what the visual shows, made only between the user's Record and stop; written to a
  temporary file inside the app until the Files sheet finishes, then deleted; the app keeps no copy
  and stores no setting about it (FR-065).
- Destination: chosen by the user in the system Files sheet. No photo library access; no new
  permission or usage description. Nothing is sent over a network.
- Content: what the visual showed. For the Camera visual this includes the camera's picture, recorded
  only by the user's own action, like a screen recording; the privacy policy says so. No audio is
  recorded (no microphone, no captured app audio).
- Metadata: none beyond the container's required fields (R8).
- App Store privacy label: still Data Not Collected (the owner confirms in App Store Connect).

## Assumptions

- "Composited frames" means the frames the active visual presents; the controls and indicators are
  app UI, not part of the frame.
- One visual and one output exist at a time (OUT-001).
- projectM recording needs a GPU-side path from ANGLE's surface that this row does not build; it is a
  follow-up (recorded in the ADR), not claimed here.
- Device behavior (encoder speed, thermal state, HEVC availability, the Files sheet with large files)
  is checked last, on devices, by the owner (`{device}` tasks).
- Simulator results are never device evidence (Constitution X).
