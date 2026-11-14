# Feature Specification: MED-003 Video Loop Region

**Feature Branch**: `feature/med-003` (spec directory `106-med-003-video-loop-region`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MED-003 (Video loop region) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Choose in and out points and
repeat seamlessly." Acceptance, verbatim: "Playback never seeks outside saved region and recovers
after end-of-file." Verification: simulator fixture media + device picker. Depends on MED-002
(integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MED-003-R1…`, success criteria `MED-003-S1…`, tasks `MED-003-T01…`. Other
features are cited by their own IDs: MED-002-R9 to R15 (playback clock, bounded queue, whole-file
loop, decoder boundary), MED-014 (container check before every open), CMP-006 (fit; the precedent
for an optional scene field), SCN-001/SCN-002/SCN-010 (scene format, autosave, undo), SHOW-001
(show cues), QA-004 (scene migration matrix).

## Baseline: what exists today (audit of 2026-11-14, commit `63867693`)

The row's gap status is "Gap candidate". The audit confirms the gap: there are no in or out points
anywhere; the whole file always loops.

| Area | Behaviour today | Gap for this row |
|---|---|---|
| Looping (MED-002-R11) | `VideoDecodePipeline`'s decode thread reads the file from the start; at the end (`next()` returns nil) it reopens the reader at 0 and counts `loops`. The playback timeline is unwrapped (`loop × duration + pts`), so playback time only increases. | Only the whole file; no region. |
| Seeking (MED-002-R10) | When the render side's playback time is more than 1 s past the next picture (a stall), the reader is reopened at `playback mod duration` (`seeks`). A resume after background restarts the session at the clock's playback time. | Seeks may land anywhere in the file. |
| End of file | A pass that produced no picture, or any reader error (`.damaged`), ends the session as `.failed`; the layer then draws the transparent fallback and the app shows "The video couldn't be played." until the content changes. | An error near the end of an otherwise good file is not recovered. |
| Damaged copy (MED-014) | Every open re-runs `VideoContainerCheck`; a damaged or replaced copy fails at the next open as `.damaged`. | Unchanged (must stay). |
| Reader (`AVVideoFrameReader`) | One `AVAssetReader` per open, `timeRange = [start, +∞)`; frames have file-relative times. | No end bound; no pre-roll. |
| Stored video (`VideoStore`) | One video; identifier in `settings.video.id`. | No per-video playback settings. |
| Scenes and show cues | A Video scene stores a `video` layer and a `video` asset `{type, storeID}`; unknown asset fields are kept verbatim (`SceneAsset.extra`). Restoring a scene never changes the stored video. | No region recorded. |
| UI | Settings → Video: summary, Choose from Photos / Files, Remove Video, notice. | No in/out control. |
| Test probe | DEBUG `videoFrameIndex` = shown picture's time on the unwrapped timeline × 30. | No file-time probe. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: What is a loop region? → A: An in point and an out point in the video's own time, in
  milliseconds; playback shows the pictures whose time lies in [in, out) and then starts again at
  in. With no region saved the whole file loops exactly as today (MED-003-R1).
- Q: What does "never seeks outside saved region" mean? → A: Every open of the video — first start,
  loop, catch-up seek, resume after background, and the restart after a region edit — starts at a
  time inside [in, out), and no picture with a time outside [in, out) is ever shown (MED-003-R3).
- Q: What does "recovers after end-of-file" mean? → A: Reaching the end of the file, or the reader
  stopping early or failing after the pass had shown at least one picture, starts the next pass at
  in without stopping playback; the event is counted. A damaged copy (the container check fails, or
  a pass shows no picture three times in a row) still falls back as today (MED-003-R5, R6).
- Q: Where is the region saved? → A: With the stored video, keyed by the video's identifier, in the
  app's settings; a new video starts with the whole file; Remove Video forgets it (MED-003-R7).
  Video scenes and show cues record it as an optional field of the video asset (MED-003-R8).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Loop only the part of the clip I want (Priority: P1)

A VJ imports a 20-second clip but only wants seconds 4 to 7 behind the spectrum. In Settings →
Video they set In to 4 s and Out to 7 s. The video now repeats those three seconds without a
visible stall at the joint, through pauses, backgrounding and relaunches.

**Why this priority**: It is the row's observable behaviour.

**Independent Test**: With a fixture whose pictures encode their index, set a region and play
across several loop boundaries: every shown picture lies inside the region, the wrap goes from the
last picture before out to the first picture at in, and no extra frames are held at the joint when
the decoder keeps up.

**Acceptance Scenarios**:

1. **Given** a stored video and no region, **When** it plays, **Then** the whole file loops as
   before.
2. **Given** a region [in, out), **When** playback reaches out, **Then** the next picture is the
   first one at or after in, with no picture outside the region in between.
3. **Given** a region, **When** the app is paused, backgrounded or relaunched, **Then** playback
   resumes inside the region.
4. **Given** a region, **When** the user taps Reset, **Then** the whole file loops again.

---

### User Story 2 - Edit the region while it plays (Priority: P1)

While the video plays, the VJ moves In or Out. Playback continues at the current picture if it is
still inside the new region, otherwise it jumps to the new In; it never shows a picture outside.

**Why this priority**: Regions are tuned live.

**Independent Test**: Change the region mid-play (fake reader and fixture): no shown picture after
the change lies outside the new region.

**Acceptance Scenarios**:

1. **Given** playback at 5 s in a region [4, 7), **When** Out becomes 6 s, **Then** playback
   continues from 5 s and wraps at 6 s.
2. **Given** playback at 5 s, **When** In becomes 5.5 s, **Then** the next picture shown is at or
   after 5.5 s.

---

### User Story 3 - A bad ending never stops the loop (Priority: P2)

A clip whose last part cannot be read (a truncated file, or a reader that stops early) keeps
looping its region instead of falling back to a transparent layer.

**Why this priority**: The acceptance criterion's second half.

**Independent Test**: A reader that fails or ends early near the end of the region: playback
continues at in, the recovery is counted, and the session is still running.

**Acceptance Scenarios**:

1. **Given** a reader that fails after some pictures of a pass, **When** the failure happens,
   **Then** the next pass starts at in and the error is counted.
2. **Given** a damaged copy, **When** it is opened, **Then** it falls back as today.

### Edge Cases

- A region longer than the file, or with out past the end: clamped to the file's duration.
- In at or past out, or shorter than the minimum length: out is moved to in + minimum, or in is
  moved back when out is at the end.
- A region shorter than one frame interval of a slow clip: the picture that covers in is shown
  and held (never an empty pass).
- A file replaced or damaged between opens: MED-014's check fails as today.
- The region of a video that is no longer stored: forgotten.
- A scene naming a region for a video that is not the stored one: ignored (the scene's media
  warning applies as today).
- Very fast region edits (dragging a slider): applied once the value settles, not per drag step.

## Requirements *(mandatory)*

### Functional Requirements

- **MED-003-R1**: The video layer MUST accept an optional loop region (in and out points in the
  video's own time); with none it MUST behave exactly as MED-002 (whole-file loop).
- **MED-003-R2**: A region MUST be clamped to the video's duration and to a minimum length of
  0.25 s (out ≥ in + 0.25 s); a video shorter than the minimum plays whole.
- **MED-003-R3**: Every open of the video (start, loop, catch-up seek, resume, region edit) MUST
  start inside [in, out), and no picture whose time is outside [in, out) MAY be shown, except the
  single picture that covers in when no picture starts inside the region.
- **MED-003-R4**: At out, playback MUST continue with the first picture at or after in on the same
  increasing playback timeline (no pause, no repeated time); the next pass MUST be prepared before
  out is reached so that, when the decoder keeps up, the joint shows no held picture.
- **MED-003-R5**: The end of the file, an early end of the reader, or a reader error after the
  pass had produced at least one picture MUST start the next pass at in without stopping
  playback, and MUST be counted (loops, early ends, recovered errors).
- **MED-003-R6**: A failed open (including MED-014's container check) or three passes in a row
  with no picture MUST end playback as `.failed` (the MED-002 fallback and notice).
- **MED-003-R7**: The region MUST be saved with the stored video, keyed by its identifier, and
  restored after relaunch; a different video MUST start with the whole file; Remove Video MUST
  forget the region; UI tests' reset flag MUST clear it.
- **MED-003-R8**: Video scenes (autosave, undo history) and show cues MUST record a non-whole
  region as an optional field of the video asset, without a format version change; restoring a
  scene whose video is the stored one MUST apply its region (none: the whole file); older scenes
  MUST load and re-save unchanged.
- **MED-003-R9**: Settings → Video MUST offer In and Out controls and Reset Loop while a video is
  stored and its duration is known; their VoiceOver values MUST read times as "1.5 seconds"; they
  MUST work at accessibility text sizes and use no animation outside the app's motion policy.
- **MED-003-R10**: A region edit MUST continue at the current picture when it lies inside the new
  region, otherwise at in, and MUST be applied once per settled edit.
- **MED-003-R11**: The region rules (clamping, timeline mapping, recovery) MUST be testable
  without a graphics device on every platform the packages' tests run on (the fake reader).
- **MED-003-R12**: DEBUG diagnostics MUST expose the shown picture's index in the file and the
  applied region, so UI tests can check that indices stay inside the region.

### Key Entities

- **Loop region**: in and out (milliseconds of the video's own time); "whole file" when absent.
- **Effective region**: the loop region clamped to the opened video's duration and the minimum.
- **Stored loop**: the region plus the video identifier it belongs to.

## Privacy review *(Constitution, Privacy; extends MED-002's review)*

| Question | Answer |
|---|---|
| What is stored? | Two numbers (in, out) and the video's identifier, in the app's own settings. |
| Is anything sent or analysed? | No. |
| Does it read anything new from the video? | No: only the duration and picture times the player already reads. |
| App Store privacy label | Unchanged: Data Not Collected. |

Result: the review passes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MED-003-S1**: Over at least three loop boundaries with an index-encoded fixture, 100 % of
  shown pictures lie inside the region, each wrap goes from the last picture before out to the
  first picture at in, and with a decoder that keeps up the joint holds no picture longer than
  one frame interval (gap 0 frames).
- **MED-003-S2**: After a stall seek, a resume and a region edit, 100 % of shown pictures lie
  inside the (new) region.
- **MED-003-S3**: Clamping: a table of regions (inverted, too short, past the end, longer than the
  file, negative) gives the expected effective region in every case.
- **MED-003-S4**: An injected early end and an injected reader error near the end each continue
  at in with the event counted and the session still running; a damaged copy fails as before.
- **MED-003-S5**: Scenes and show cues round-trip the region; a scene without one loads and
  re-saves byte-identically.
- **MED-003-S6**: In a DEBUG UI test on the simulator, a seeded video with In and Out set shows
  only picture indices inside the region, within 30 seconds of test time.
- **MED-003-S7** (device stage): on D1, a video picked with the system picker, looped over a
  region, shows no visible stall at the joint.

## Assumptions

- The region is per stored video; the app stores one video at a time (MED-002).
- Speed (MED-004) and reverse (MED-005) are separate rows.
- Device behaviour (MED-003-S7) is verified only in the final device stage.
