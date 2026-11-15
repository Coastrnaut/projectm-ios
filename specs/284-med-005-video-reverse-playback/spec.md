# Feature Specification: MED-005 Video Reverse Playback

**Feature Branch**: `feature/med-005` (spec directory `284-med-005-video-reverse-playback`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-15 (MED-005-T01-T19 verified on the Mac host and the iOS 27.2 simulator; device task T20 `{device}` open; report `docs/test-reports/video-reverse-playback.md`)

**Input**: User description: "Implement MED-005 (Video reverse playback) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Provide cached reverse playback
only for supported local clips." Acceptance, verbatim: "Short fixture reverses frame order and
unsupported clips show clear error." P3, size L. Depends on MED-002 (integrated)."

Identifiers carry the roadmap ID so they never collide with other features: requirements are
`MED-005-R1…`, success criteria `MED-005-S1…`, tasks `MED-005-T01…`. Other features are cited by
their own IDs: MED-002 (video layer, playback clock, stored copy without sound), MED-003 (loop
region), MED-004 (speed), MED-008 (animated images: decoded-frame byte budget by device class),
MED-014 (safe media decoder), FILE-005 (backup key policy), FILE-008 (content-addressed video
store), FILE-011 (local data erase), CMP-013 (the video layer is never render-cached).

## Baseline: what exists today (audit of 2026-11-14, commit `268f5beb`)

The row's gap status is "Gap candidate". The audit confirms the gap: the video only plays forward.

| Area | Behaviour today | Gap for this row |
|---|---|---|
| Stored copy (MED-002, FILE-008) | One imported video, remuxed into `Library/Application Support/Videos` without soundtrack or metadata; H.264/HEVC, ≤ 4096 px, ≤ 60 fps, ≤ 500 MB. Always a local file; protected or remote media cannot be imported (the remux reads every sample). | Nothing says which clips can be reversed. |
| Decode (MED-002-R9 to R11) | One decode thread reads pictures forward with `AVAssetReader` into a 3-picture queue; the timeline only increases; the reader loops at the end of the file or region. | Pictures are read forward only; nothing is kept once shown. |
| Clock (MED-002-R9, MED-004) | `VideoPlaybackClock` advances by injected presentation steps × speed (integer arithmetic). | Reused: reverse picks pictures from the same video time. |
| Loop region (MED-003) | `settings.video.loop`; playback repeats [in, out). | Reverse must respect it. |
| Speed (MED-004) | `settings.video.speed`; a Speed picker in Settings → Video. | Reverse must respect it; the new control sits next to it. |
| Frame cache (MED-008) | `AnimatedFrameBudget`: 32 / 64 / 128 MB by device memory class; `accountedFrameBytes` (RGBA8, one pixel of slack per side); `AnimatedFrameCache` evicts least recently used frames. | Reused for the budget and the per-picture accounting; reverse needs every cached picture resident, so no eviction. |
| Render caching (CMP-013) | The video layer is never cached by the compositor; it renders every frame. | Unchanged. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Which clips can be reversed? → A: The stored (local, imported) video only, when its video
  track is at most 30 seconds long and its upright picture fits 1080p (longest side ≤ 1920 and
  shortest side ≤ 1080), and every picture decodes. Remote, iCloud-only and protected media never
  reach the store (the import copies and remuxes the file locally), so they cannot be selected;
  a stored copy that fails to decode is "unsupported" like any other (MED-005-R2).
- Q: How is reverse made possible? → A: Cached: the clip is decoded once, in the background,
  into a bounded cache of downsampled pictures, and reverse playback picks pictures from that
  cache. Rejected: segment reads (decode a group of pictures forward, emit it backwards), which
  decode most pictures several times per loop and still need a group of full-size pictures in
  memory (MED-005-R3).
- Q: What does an unsupported clip do? → A: It keeps playing forward, and Settings → Video shows
  one clear sentence that names the limit, for example "Reverse playback is available for clips
  up to 30 seconds. This video plays forward." (MED-005-R5).
- Q: What happens to sound? → A: Nothing: the stored copy has no soundtrack (MED-002-R16) and the
  music comes from the chosen audio source, which never changes direction (MED-005-R8).
- Q: Is reverse saved? → A: Yes, like speed and loop: with the stored video, keyed by its
  identifier (`settings.video.reverse`), never in a backup, erased with "Photos and videos",
  forgotten by Remove Video and a new video (MED-005-R7).

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rules 4 and 9).

- Q: Where does reverse start when it is turned on? → A: At the picture shown last (continuous: the
  picture does not jump), or at out when nothing was shown yet or the shown picture lies outside
  the loop region (MED-005-R4).
- Q: What does the user see while the cache is prepared? → A: The clip keeps playing forward and
  the Reverse row's caption reads "Preparing reverse…" until reverse starts; no notice and no
  spinner over the visual (MED-005-R1, R6).
- Q: How large are cached pictures? → A: As large as the budget allows for this clip, never larger
  than the clip's own picture: every cached picture plus two transient ones must fit the budget
  (for a 30 s 1080p clip: 125 × 70 at 32 MB, 177 × 99 at 64 MB, 252 × 141 at 128 MB, measured by MED-005-T03); the forward picture is unchanged
  (MED-005-R3).
- Q: Do scenes, undo and show cues record the direction? → A: No. Direction is a playback choice
  of the stored video, like the video itself in Settings; restoring a scene never changes it and
  no scene field is added (no format change, QA-004 unaffected).
- Q: How is the unsupported message delivered to VoiceOver? → A: Announced once, through the same
  announcement path as the Video section's other notices (MED-002-R14), when it first appears, and shown as the Reverse row's caption while
  Reverse is on (MED-005-R5).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Play a short clip backwards (Priority: P1)

A VJ has imported an 8-second clip of falling water. In Settings → Video they turn on Reverse;
after a moment of preparation the water rises. The music and spectrum are unchanged.

**Why this priority**: It is the row's observable behaviour and the first half of its acceptance.

**Independent Test**: Generate a 12-picture clip whose pictures encode their index, turn reverse
on, and step an injected clock one picture interval at a time: the shown pictures are 11, 10, …, 0
in exactly that order, at the expected times.

**Acceptance Scenarios**:

1. **Given** a supported stored clip, **When** Reverse is turned on, **Then** once the cache is
   ready the pictures play in descending order, one per picture interval of the clip.
2. **Given** reverse playback, **When** the first picture is reached, **Then** playback wraps to
   the last picture (the video always loops) and continues backwards.
3. **Given** reverse and a speed (MED-004), **When** it plays, **Then** the pictures move
   backwards at that speed.
4. **Given** reverse and a loop region (MED-003), **When** it plays, **Then** it moves from out
   back to in and wraps from in back to out.
5. **Given** Reverse on, **When** the app is relaunched, **Then** the clip plays backwards again
   (after the cache is prepared again).

---

### User Story 2 - A clip that cannot be reversed says so (Priority: P1)

The VJ imports a 2-minute concert clip and turns on Reverse. The clip keeps playing forward and
Settings shows "Reverse playback is available for clips up to 30 seconds. This video plays
forward."

**Why this priority**: The second half of the acceptance criterion.

**Independent Test**: A clip over 30 s (by its track facts) and a corrupt stored copy: each gives
its message, reverse never starts, and forward playback continues.

**Acceptance Scenarios**:

1. **Given** a clip longer than 30 s, **When** Reverse is on, **Then** the duration message is
   shown and the clip plays forward.
2. **Given** a clip larger than 1080p, **When** Reverse is on, **Then** the size message is shown
   and the clip plays forward.
3. **Given** a stored copy that cannot be decoded, **When** Reverse is on, **Then** the "can't be
   played in reverse" message is shown and nothing crashes.
4. **Given** the message, **When** Reverse is turned off or another video is chosen, **Then** the
   message disappears.

---

### User Story 3 - Memory stays bounded (Priority: P2)

Reversing the largest supported clip on the smallest device never exceeds this device class's
decoded-picture budget.

**Why this priority**: Unbounded caches get the app killed in a live set.

**Independent Test**: For the largest supported shape (30 s, 1920 × 1080, 60 fps) and each device
class, the planned cache and its peak accounted bytes stay within the budget; a small real cache
records its peak.

**Acceptance Scenarios**:

1. **Given** any supported clip, **When** its cache is built, **Then** the peak accounted bytes
   never exceed the budget.
2. **Given** the app goes to the background, **When** it stays there, **Then** the cache is
   released, and it is rebuilt on return.

### Edge Cases

- Reverse turned on while the cache is being prepared: forward playback continues until it is
  ready; turning Reverse off cancels the preparation.
- A clip above 30 pictures per second: the cache keeps at most 30 pictures per second (a 60 fps
  clip keeps every other picture), so reverse shows at most 30 different pictures per second.
- Turning Reverse off: forward playback resumes at the picture shown last.
- A new video or Remove Video: reverse is off for the new video and the message disappears.
- A stored reverse value for another video, or malformed: reads as off and is removed.
- Scenes, undo and show cues do not record direction: restoring a scene never changes Reverse.
- No video stored: the Reverse switch is hidden.
- Reduce flashing (FR-072): the compositor's flash guard applies to reversed pictures as to any.

## Requirements *(mandatory)*

### Functional Requirements

- **MED-005-R1**: Settings → Video MUST offer a "Reverse" switch next to Speed whenever a video is
  stored; turning it on MUST request reverse playback of the stored video, off MUST return to
  forward playback at the picture shown last.
- **MED-005-R2**: Reverse MUST be offered only for supported clips: video track ≤ 30 s, upright
  picture ≤ 1920 × 1080 (longest side ≤ 1920, shortest ≤ 1080), decodable. The check MUST use
  the track facts before any picture is cached.
- **MED-005-R3**: A supported clip MUST be decoded once, off the render path, into a cache of
  pictures at no more than 30 per second, downsampled so that every cached picture plus two
  transient ones fit the device class's decoded-picture budget (MED-008: 32 / 64 / 128 MB); the
  accounted bytes MUST never exceed the budget, and the peak MUST be recorded.
- **MED-005-R4**: While reversed, the shown picture MUST be a pure function of the video time
  (the MED-002/MED-004 clock: injected presentation steps × speed): with the effective region
  [in, out) of length L and the reverse start offset, media time m = out − 1 ns − (t mod L), and
  the shown picture is the last cached picture at or before m (never before in). Playback MUST
  wrap from in back to out.
- **MED-005-R5**: An unsupported clip MUST keep playing forward and MUST show exactly one plain
  message while Reverse is on: too long → "Reverse playback is available for clips up to 30
  seconds. This video plays forward."; too large → "Reverse playback is available for clips up to
  1080p. This video plays forward."; undecodable → "This video can't be played in reverse. It
  plays forward." The message MUST be announced once and MUST disappear when Reverse is off or
  the video changes.
- **MED-005-R6**: The render path MUST never decode, wait or allocate for reverse: it MUST read the
  cache's state with a lock taken only when free; until the cache is ready, forward playback
  continues. The forward decoder MUST be stopped while the cache plays, and restarted at the shown
  picture when Reverse ends.
- **MED-005-R7**: The reverse choice MUST be saved with the stored video (`settings.video.reverse`,
  keyed by the video identifier) and restored after relaunch; a different video, Remove Video, the
  UI tests' reset and FILE-011's "Photos and videos" erase MUST clear it; it MUST be excluded from
  backups (FILE-005).
- **MED-005-R8**: Reverse MUST change only the video layer; the chosen audio source and analysis
  MUST be untouched, and no sound is ever played from the video.
- **MED-005-R9**: In the background, on scene loss or presentation loss the cache MUST be released
  with the decoder (MED-002-R13), and rebuilt on resume while Reverse is on.
- **MED-005-R10**: The eligibility, sizing, timeline and accounting rules MUST be plain Swift,
  testable without a graphics device on every platform the package builds on (Linux included).
- **MED-005-R11**: The DEBUG diagnostics MUST expose the reverse state and the shown picture's
  media index so UI tests can check it.

### Key Entities

- **Reverse limits**: maximum duration (30 s), maximum upright size (1920 × 1080), cache rate
  (30 pictures per second).
- **Reverse plan**: the cached picture size and count for one clip and budget.
- **Reverse timeline**: the cached pictures' media times; the shown picture for a video time.
- **Reverse state**: off, preparing, playing, unsupported(reason).
- **Stored reverse choice**: `{id}` in `settings.video.reverse`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MED-005-S1**: For a generated 12-picture clip, reverse playback shows pictures 11 down to 0 in
  exactly descending order, each at its expected time, then wraps to 11.
- **MED-005-S2**: A clip over 30 s and a corrupt clip each show their message, and forward
  playback continues (the shown picture keeps advancing forward).
- **MED-005-S3**: For the largest supported clip on each device class, the peak cache bytes stay
  within the budget (32 / 64 / 128 MB).
- **MED-005-S4**: Reverse survives a relaunch, and is cleared by Remove Video and a new video.
- **MED-005-S5**: The Reverse switch can be turned on in Settings and reaches the player within
  5 s on the simulator fixture (a ceiling, not a timing assertion).

## Assumptions

- The one stored video (MED-002) is the only reversible content; camera and photo layers are
  out of scope.
- A downsampled cache is acceptable picture quality for reverse (a VJ background); the forward
  picture quality is unchanged.
- Device checks (memory and smoothness on D1-D3) are `{device}` tasks.
