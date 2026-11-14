# Feature Specification: MED-004 Video Playback Speed

**Feature Branch**: `feature/med-004` (spec directory `124-med-004-video-playback-speed`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MED-004 (Video playback speed) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Adjust speed within a safe
range independently of audio source." Acceptance, verbatim: "Half-speed fixture advances one
second per two seconds elapsed." Verification: simulator fixture media + device picker. Depends on
MED-002 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MED-004-R1…`, success criteria `MED-004-S1…`, tasks `MED-004-T01…`. Other
features are cited by their own IDs: MED-002-R9 to R16 (playback clock, bounded queue, whole-file
loop, no soundtrack), MED-003-R1 to R10 (loop region, pre-roll, storage, scene field), FILE-005
(backup key policy), FILE-008 (content-addressed video store), FILE-011 (local data erase),
CMP-013 (video is never cached), SCN-002/SCN-010 (autosave, undo), SHOW-001 (show cues), ACC-005
(accessible parameters), ACC-006 (large text).

## Baseline: what exists today (audit of 2026-11-14, commit `13491ae3`)

The row's gap status is "Gap candidate". The audit confirms the gap: the video always plays at 1×.

| Area | Behaviour today | Gap for this row |
|---|---|---|
| Playback clock (MED-002-R9) | `VideoPlaybackClock` adds the difference between successive presentation times (the display link's target times; injected times in tests) to the playback time: a step in (0, 1 s] is added in full, a larger step (pause, background) or a step ≤ 0 adds nothing. Its header already notes "MED-004 (speed) scales the added difference". | No speed: one second of presentation is one second of video. |
| Timeline (MED-002-R10, R11; MED-003-R4) | The decode queue's timeline is the video's own time, unwrapped: `base + k × L + (pts − in)`; `take(upTo:)` returns the newest picture due at the clock's playback time and drops older due ones as late; more than 1 s behind, the reader seeks. | Already in media time, so a speed multiplier on the clock needs no change in the queue's mapping. |
| Pre-roll (MED-003-R4) | The pass at in is prepared when the picture read is within 0.5 s (of media time) of out. | At 2×, 0.5 s of media is only 0.25 s of wall time. |
| Soundtrack (MED-002-R16) | The stored copy is remuxed without any audio track (`VideoSanitizer`); the reader reads the video track only; the spectrum reads the app's chosen audio source. | None: the video has no sound that could change speed. |
| App audio source | In-App Playback, Microphone and System/App Capture have their own transports in CaptureKit; the video layer's package (`VideoLayer`) depends on no audio or capture module. | Must stay so: speed must never reach the audio source. |
| Storage (MED-003-R7) | `settings.video.id` and `settings.video.loop` (`{id, inMilliseconds, outMilliseconds}`); both excluded from FILE-005 backups; FILE-011's "Photos and videos" erase removes both. | No speed key. |
| Scenes (MED-003-R8) | The video asset may carry an optional `loop` object, kept verbatim by older apps (no version change). | No speed field. |
| UI (MED-003-R9) | Settings → Video: summary, pickers, Loop in / Loop out sliders, Reset Loop, Remove Video. | No speed control. |
| Probes | DEBUG `videoFrameIndex` = the shown picture's time on the unwrapped timeline × 30; `videoMediaFrameIndex`, `videoLoopRegion`, `videoLoopStats`. | No speed probe. |
| Caching (CMP-013) | The video layer is never cached; it renders every frame. | Unchanged. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: What is the safe range? → A: Seven fixed speeds: 0.25×, 0.5×, 0.75×, 1× (default), 1.25×,
  1.5× and 2×. No zero (pausing is the visualizer's Pause, FR-046) and nothing above 2× (decoding
  four times the pictures of a 60 fps 4K clip is not a safe default on the reference devices).
  Stored as an integer percentage (25…200) so no rounding drift is possible (MED-004-R1).
- Q: What does speed change? → A: Only how fast the video layer's own time advances: per frame
  the elapsed presentation time is multiplied by the speed. The video's soundtrack does not exist
  (removed at import) and the app's audio source (In-App Playback, Microphone, System/App Capture)
  is never touched: its transport, rate and analysis stay exactly as they are (MED-004-R2, R3).
- Q: What does "advances one second per two seconds elapsed" mean? → A: At 0.5×, after 2 s of
  elapsed presentation time the video's time has advanced by 1 s, within one picture interval of
  the clip (MED-004-S1), measured on an injected clock so the test needs no wall clock.
- Q: What happens to a speed change mid-play? → A: The video's time continues from where it is,
  with no jump and no restart of the decoder; only the rate of advance changes from the next
  frame (MED-004-R4).
- Q: Where is speed saved? → A: Like the loop region: with the stored video in the app's settings
  (`settings.video.speed`, keyed by the video's identifier), excluded from backups like the
  video and its loop, erased with "Photos and videos", forgotten by Remove Video and by a new
  video; scenes and show cues record it as an optional field of the video asset (MED-004-R6, R7).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Slow the video down or speed it up (Priority: P1)

A VJ plays a clip behind the spectrum and wants it calmer. In Settings → Video they choose Speed
"0.5×". The clip now moves at half speed while the music and the spectrum stay exactly as before.

**Why this priority**: It is the row's observable behaviour and its acceptance criterion.

**Independent Test**: With a fixture whose pictures encode their index and an injected clock,
advance 2 s of presentation time at 0.5×: the shown picture's time advanced by 1 s (one picture
interval tolerance). Repeat at 1× and 2×.

**Acceptance Scenarios**:

1. **Given** a stored video at 1×, **When** the user chooses 0.5×, **Then** the video's time
   advances one second per two seconds elapsed.
2. **Given** 2×, **When** two seconds elapse, **Then** the video's time advances four seconds
   (wrapping over the loop as needed).
3. **Given** any speed, **When** it plays, **Then** the chosen audio source's playback and the
   spectrum's analysis are unchanged.
4. **Given** a speed other than 1×, **When** the app is relaunched, **Then** the video plays at
   the same speed.

---

### User Story 2 - Change speed live without a jump (Priority: P1)

While the clip plays, the VJ switches from 0.5× to 2× and back. The picture never jumps back or
ahead; only how fast it moves changes.

**Why this priority**: Speed is tuned live during a set.

**Independent Test**: Change the speed mid-play on an injected clock: the video's time is
continuous at the change (the first frame after the change differs from the last one before by
exactly the new speed times the frame step).

**Acceptance Scenarios**:

1. **Given** playback at video time t, **When** the speed changes, **Then** the next frame shows
   video time t + step × new speed.
2. **Given** a speed change, **When** it happens, **Then** the decoder is not restarted.

---

### User Story 3 - Speed and the loop region work together (Priority: P2)

The VJ loops seconds 4 to 7 (MED-003) at 0.5×: the loop takes six seconds of wall time and still
repeats without a visible stall at the joint. At 2× it takes 1.5 s, also seamless.

**Why this priority**: Both settings are used together; the joint must stay seamless.

**Independent Test**: With a fake reader and a region, play across several boundaries at 0.5× and
at 2×: every shown picture lies inside the region, and with a decoder that keeps up no picture is
held past its slot at the joint (gap 0 frames).

**Acceptance Scenarios**:

1. **Given** a region and 0.5×, **When** playback crosses out, **Then** it continues at in with no
   picture outside the region and no held picture.
2. **Given** a region and 2×, **When** playback crosses out, **Then** the same holds, and the next
   pass was prepared at least as early in wall time as at 1×.

### Edge Cases

- A stored speed outside the seven values, malformed, or for another video: reads as 1× and is
  removed.
- A scene with a speed field for another video: ignored (like its loop region).
- A scene with a malformed speed field: reads as 1×; an older app keeps the field verbatim.
- Above 1× when the decoder cannot keep up: late pictures are dropped so the shown picture is
  always the one for the current video time; more than 1 s behind, the reader seeks (MED-002-R10).
  Playback never slows down to wait for the decoder.
- A pause, the background or a stall longer than 1 s: adds nothing, at any speed (MED-002-R9).
- A recording (REC-003) or a still capture: records what is shown; its own timeline is the
  presentation time, unchanged by speed.
- Remove Video, or a new video: the speed returns to 1×.

## Requirements *(mandatory)*

### Functional Requirements

- **MED-004-R1**: The video layer MUST accept a playback speed from a fixed set (0.25×, 0.5×,
  0.75×, 1×, 1.25×, 1.5×, 2×); 1× MUST behave exactly as MED-002/MED-003. Any other value MUST be
  rejected (read as 1×).
- **MED-004-R2**: Per frame, the video's time MUST advance by the elapsed presentation time
  multiplied by the speed, using exact integer arithmetic (no drift over any length of playback);
  MED-002-R9's rules for steps above 1 s or ≤ 0 MUST apply to the elapsed presentation time.
- **MED-004-R3**: The speed MUST apply only to the video layer: the chosen audio source's
  transport, rate and analysis, and every other layer's timing, MUST NOT change; the video's
  soundtrack MUST stay removed and unread (MED-002-R16).
- **MED-004-R4**: A speed change MUST keep the video's time continuous (no jump) and MUST NOT
  restart the decoder; the new speed applies from the next frame.
- **MED-004-R5**: The loop region (MED-003) MUST stay in the video's own time: its joint MUST stay
  seamless at every speed, and the next pass MUST be prepared at least 0.5 s of wall time before
  out at speeds above 1× (the pre-roll lead in video time grows with the speed).
- **MED-004-R6**: The speed MUST be saved with the stored video, keyed by its identifier, and
  restored after relaunch; a different video, Remove Video and the UI tests' reset MUST return to
  1×; the key MUST be excluded from backups (FILE-005) like the video and its loop, and FILE-011's
  "Photos and videos" erase MUST remove it.
- **MED-004-R7**: Video scenes (autosave, undo history) and show cues MUST record a speed other
  than 1× as an optional integer field of the video asset, without a format version change; a
  malformed value MUST read as 1×; restoring a scene whose video is the stored one MUST apply its
  speed (absent: 1×); older scenes MUST load and re-save unchanged.
- **MED-004-R8**: Settings → Video MUST offer a Speed control with the seven values while a video
  is stored; VoiceOver MUST read each value in words ("half speed", "normal speed", "1.5 times",
  "double speed"); the footer MUST say that speed changes only the video, never the music; it
  MUST work at accessibility text sizes and use no animation outside the app's motion policy.
- **MED-004-R9**: Above 1× the shown picture MUST always be the one for the current video time:
  late pictures are dropped, and the reader seeks when more than 1 s behind; playback MUST NOT
  slow down to wait for the decoder.
- **MED-004-R10**: The speed arithmetic MUST be testable without a graphics device on every
  platform the packages' tests run on (injected clock, fake reader).
- **MED-004-R11**: DEBUG diagnostics MUST expose the applied speed and the measured ratio of video
  time to presentation time since the last speed change, so UI tests can check the rate without
  a wall clock.

### Key Entities

- **Playback speed**: an integer percentage, one of 25, 50, 75, 100, 125, 150, 200.
- **Stored speed**: the speed plus the video identifier it belongs to.
- **Scene speed**: the optional integer field of a scene's video asset.

## Privacy review *(Constitution, Privacy; extends MED-002's and MED-003's reviews)*

| Question | Answer |
|---|---|
| What is stored? | One integer and the video's identifier, in the app's own settings. |
| Is anything sent or analysed? | No. |
| Does it read anything new from the video? | No. |
| App Store privacy label | Unchanged: Data Not Collected. |

Result: the review passes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MED-004-S1** (the acceptance): at 0.5×, 2 s of elapsed presentation time advance the video's
  time by 1 s within one picture interval; at 1× by 2 s; at 2× by 4 s; measured on an injected
  clock, with the shown picture of an index-encoded fixture matching the expected video time.
- **MED-004-S2**: A speed change mid-play gives a continuous video time (0 ns jump beyond the new
  step) and no decoder restart.
- **MED-004-S3**: Over at least three loop boundaries at 0.5× and at 2×, 100 % of shown pictures
  lie inside the region and the joint holds no picture past its slot with a decoder that keeps up
  (gap 0 frames).
- **MED-004-S4**: Changing the speed touches no audio source state (the audio transport and its
  clock are unchanged in a test), and the video layer's module depends on no audio module.
- **MED-004-S5**: The speed survives relaunch; a new video, Remove Video and the "Photos and
  videos" erase return it to 1×; backups never contain it; scenes and cues round-trip it.
- **MED-004-S6**: In a DEBUG UI test on the simulator, with the seeded fixture at 0.5×, the
  measured ratio of video time to presentation time is 0.5 (± 0.05) and the shown picture keeps
  advancing, within 30 seconds of test time.
- **MED-004-S7** (device stage): on D1, a picked clip at 2× keeps up or drops late pictures without
  slowing down, and 0.25× looks smooth.

## Assumptions

- One stored video at a time (MED-002); speed is per stored video, like the loop region.
- Reverse playback is MED-005 (a separate row); speed is never negative.
- Device decoding throughput at 2× (MED-004-S7) is verified only in the final device stage.
