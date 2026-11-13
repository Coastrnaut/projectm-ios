# Feature Specification: MED-002 Import Video Layer

**Feature Branch**: `feature/med-002` (spec directory `048-med-002-import-video-layer`)

**Created**: 2026-11-13

**Status**: Planned (analysis fixes applied 2026-11-13)

**Input**: User description: "Implement MED-002 (Import video layer) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Choose compatible local video
and render frames as a layer." Acceptance, verbatim: "Video plays at intended rate with bounded
decode queue." Verification: simulator fixture media + device picker. Depends on CMP-001
(integrated: Packages/Compositor, ADR-0013) and follows MED-001 (imported photo layer, ADR-0020).
Leave room for MED-003 (loop region), MED-004 (playback speed), MED-005 (reverse playback), MED-013
(relinking) and MED-014 (safe media decoder); implement only MED-002."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MED-002-R1…`, success criteria `MED-002-S1…`, tasks `MED-002-T01…`. Requirements
of other features are cited by their own IDs: CMP-001-R1 to R11 (the layer contract), CMP-002-R1
(stack order), CAM-001-R7 (a visual's frame loop runs only while shown), MED-001-R1 to R18 (the
photo layer this row mirrors), FR-065 (what the app may store), FR-068 (no networking).

The video is user content brought into the app; the constitution's Privacy section asks for a
privacy review of any new kind of stored user data. This specification's "Privacy review" section
is that review.

## Baseline: what exists today (audit of 2026-11-13, commit `b2d557d`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Video import | Nothing imports, decodes or stores video. MED-001 imports one still image (Photos and Files pickers, a pixels-only copy in Application Support); CAM-001 shows the live camera. `CaptureKit`'s in-app playback plays audio files only. | No way to bring a video into the app. |
| Layers | CMP-001's compositor draws layers; the camera and the photo are picture layers under the circular spectrum, built through CMP-002's `LayerStack`. | No layer shows moving pictures from a file, so nothing paces frames to a file's own timeline. |
| App | Settings › Visual offers projectM, Circular Spectrum, Linear Spectrum, Camera and Photo. | No video visual, no stored video, no remove action. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Should the app keep the picked video file as it is (and never read its metadata), or store a new copy without metadata? → A: A new copy without metadata, made without re-compressing: the video pictures are copied sample for sample (a "remux") into a new movie file that has only the video track and its timing, so location, creation date, device and any other metadata, and the soundtrack, never reach the app's storage. Re-encoding was rejected (minutes of work and battery for a long 4K file, and a quality loss); keeping the original was rejected (its location would sit in the container and in backups even if never read). If the copy cannot be written this way the import fails with "couldn't be saved"; nothing else is stored.
- Q: What happens at the end of the video: loop from the start, or hold the last picture? → A: Loop the whole video, with the playback timeline continuing so there is no gap and no frozen picture (a background video is expected to keep moving). Holding the last picture was rejected (the layer would look broken after a short clip). MED-003 replaces "the whole video" with a saved region.
- Q: Is the imported video's own sound played or analysed? → A: Neither, and it is not stored: the soundtrack is dropped when the copy is made. The visualizer's audio source stays the viewer's chosen source (music app, file, microphone). Mixing the video's sound into the source belongs to a later, separate decision.
- Q: Which videos are accepted? → A: H.264 or HEVC video, a picture at most 4096 pixels on its longest side (4K UHD and DCI fit; 8K is refused), a nominal frame rate of at most 60 frames per second (59.94 fits; 120 and 240 fps slow-motion masters are refused), and a picked file of at most 500 MB. ProRes, AV1 and other codecs are refused as "not supported". MED-014 may tighten or add checks behind the same decoder boundary.
- Q: After a relaunch, does the video continue where it was or start from the beginning? → A: From the beginning. Only the chosen video is remembered (like the photo); the playback position is not stored, so nothing about viewing is kept. Within a session a pause or the background continues from the picture it stopped at (R9, R13).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose a video and see it play behind the music (Priority: P1) — MVP

A viewer opens Settings, chooses the "Video" visual, taps "Choose from Photos…" (or "Choose from
Files…"), and picks one video. The app copies the video into its own storage and plays its
pictures full screen, at the video's own speed, behind the circular spectrum. The music keeps
coming from the source the viewer chose; the video's own sound is not played. The original is
never uploaded and the app gets no access to the rest of the library.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: A test-only launch flag puts a generated fixture video through the same
import path (system pickers cannot be automated); choose Video; the video layer reports the video's
size and the index of the frame it shows, which advances.

**Acceptance Scenarios**:

1. **Given** the Video visual with no video, **When** the viewer picks a compatible video, **Then**
   its pictures play behind the spectrum and Settings shows its size, length and a "Remove Video"
   button.
2. **Given** a playing 30 frames-per-second video, **When** t seconds of display time pass,
   **Then** the frame shown is the one the file shows at t (frame ⌊t × 30⌋), never one ahead.
3. **Given** a picked video with location and other metadata and a soundtrack, **When** it is
   imported, **Then** the stored copy holds only the video pictures and their timing: no location,
   no other metadata, no soundtrack.
4. **Given** the Photos picker, **When** it is shown, **Then** iOS asks for no photo library
   permission.

---

### User Story 2 - Playback stays smooth and bounded (Priority: P1)

Whatever the display does (a slow frame, a stall, a pause, the app in the background), the video
keeps to its own clock, never builds up a backlog of pictures in memory, and skips pictures it is
too late to show instead of showing them late.

**Why this priority**: It is the row's acceptance ("bounded decode queue").

**Independent Test**: Package tests with a fake clock: the number of decoded pictures waiting is
counted and never exceeds the bound, through normal playback, a stall, a jump ahead and a stop;
late pictures are counted as dropped; the shown picture always matches the time.

**Acceptance Scenarios**:

1. **Given** a playing video, **When** the display stops asking for frames, **Then** decoding stops
   once the small queue is full and resumes when frames are taken.
2. **Given** a playing video, **When** display time jumps ahead by more than a second, **Then** the
   pictures in between are skipped (dropped or jumped over), the shown picture matches the new time,
   and the queue stays within its bound.
3. **Given** the video reaches its end, **When** time goes on, **Then** it starts again from the
   beginning without a gap or a frozen picture.
4. **Given** the visualizer is paused or the app goes to the background, **When** it resumes,
   **Then** the video continues from the picture it stopped at.

---

### User Story 3 - The video is still there after relaunch, and can be removed (Priority: P1)

The viewer closes the app and opens it again: the Video visual plays the same video. "Remove Video"
deletes the copy and the visual returns to the spectrum over black.

**Why this priority**: Persistence matches MED-001; removal is the privacy control.

**Independent Test**: The UI test seeds a fixture, sees frames advance, terminates the app,
relaunches it without the seed flag, sees frames advance again, then taps Remove Video and sees "No
video". Unit tests check the store (copy, replace, remove, invalid identifiers).

**Acceptance Scenarios**:

1. **Given** an imported video, **When** the app is opened again, **Then** the same stored copy plays,
   from its beginning (the playback position is not stored).
2. **Given** an imported video, **When** the viewer taps Remove Video, **Then** the copy no longer
   exists and the next frame shows no video.

---

### User Story 4 - Incompatible or broken files never break the app (Priority: P2)

The viewer picks something that cannot be used: not a video, a damaged file, a file over the size
limit, a picture larger than 4K, more than 60 frames per second, or a codec the app does not play.
A short notice names the reason; the visual keeps running; the previous video, if any, stays. A
stored copy that turns out to be damaged while playing shows nothing (transparent) and a notice; the
spectrum keeps running.

**Why this priority**: MED-014 builds on it; a crash or a frozen visual is worse than no video.

**Independent Test**: Package tests feed corrupt, truncated, non-video and over-limit fixtures to
the importer and the player and expect typed errors and the transparent fallback.

**Acceptance Scenarios**:

1. **Given** a stored video, **When** a damaged file is picked, **Then** a notice says the video
   could not be read and the stored video is unchanged.
2. **Given** a stored copy that fails to decode during playback, **When** the failure happens,
   **Then** the layer shows its transparent fallback, a notice names it, and the other layers keep
   drawing.

### Edge Cases

- The viewer cancels a picker: nothing changes, no notice.
- A portrait video recorded on a phone (stored sideways with a rotation): it is shown upright.
- A video wider or taller than the screen's shape: it fills the screen keeping its aspect ratio and
  crops the overflow equally on both sides (like Camera and Photo).
- A 4K60 or a long (an hour or more) video within the size limit: accepted; memory stays bounded by
  the queue, not by the file's length (device task on D1 and D3).
- A variable frame-rate video (phone recordings): each picture is shown for as long as its own
  timing says.
- A high dynamic range (HDR) video: shown in standard range; the brightest highlights are clipped
  (device task).
- A video with no pictures (audio only, e.g. an `.m4a` renamed): refused as "not a video".
- The video's own soundtrack: removed when copied, never played, never analysed.
- A slow-motion video: plays at its file's stored timing (the picker's export decides how the slow
  part is timed); no slow-motion editing in this row.
- An iCloud Photos item not on the device: the picker downloads it out of process; if that fails,
  the notice says the video could not be read.
- Storage is full when copying: the notice says the video could not be saved; the previous video stays.
- Importing a second video replaces the first, whose copy is deleted once the new one is saved.
- The stored identifier is invalid or names a path outside the video folder: ignored, never opened.
- The visual is left or another video chosen while decoding: the old decoding stops and its
  pictures are released.
- The output size changes (rotation): playback is not restarted; only the geometry changes.
- No Metal device: the Video visual falls back to projectM with the same notice as the other
  native visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **MED-002-R1**: Settings MUST offer a "Video" visual beside the existing visuals. It shows the
  video layer at the bottom with the circular spectrum layer over it, built as a layer stack
  (CMP-002-R1: index 0 bottom).
- **MED-002-R2**: While Video is chosen, Settings MUST offer "Choose from Photos…" (the system Photos
  picker, videos only, one item) and "Choose from Files…" (the system document picker, movie types
  only, one file). The Photos picker MUST be the out-of-process picker that needs no photo library
  permission; the app MUST NOT request photo library access or declare a photo library usage
  description.
- **MED-002-R3**: A picked video MUST be copied into the app's own storage before it is used; the
  layer MUST read only that copy. Nothing about the original (its location, library identifier, file
  name) is kept after the import.
- **MED-002-R4**: The stored copy MUST contain only the video pictures and their timing, copied
  without re-compressing them: no soundtrack, no location, date, device or other metadata. The app
  MUST NOT read, show or store the original's metadata (only the facts R5 checks are read).
- **MED-002-R5**: Imports MUST be refused, with a typed reason, when the picked file is larger than
  500 MB; when it has no video pictures; when its codec is not H.264 or HEVC; when its picture is
  longer than 4096 pixels on its longest side; when its nominal frame rate is above 60 frames per
  second (rates up to 60.5 are read as 60, so 59.94 and rounded 60.0x headers pass); or when it is damaged (its first picture cannot be decoded).
- **MED-002-R6**: The app MUST keep one video at a time. Its identifier MUST be stored in the app's
  settings; a new import replaces the previous video, whose copy is deleted only after the new copy
  is saved. A failed import MUST leave the previous video and identifier unchanged.
- **MED-002-R7**: "Remove Video" MUST delete the stored copy and the identifier; the video layer then
  shows nothing from the next frame on.
- **MED-002-R8**: The Video visual choice MUST persist across launches; after a relaunch the stored
  copy MUST play from its beginning without any new choice. The playback position MUST NOT be stored.
- **MED-002-R9**: Playback MUST follow the video's own timeline at its intended rate (1×), driven by
  the display's presentation time: at playback time t the layer shows the latest picture whose
  timestamp is at or before t, never a later one. Playback time advances by the display time between
  frames; a gap longer than 1 second (a pause, the background, a long stall) does not advance it, so
  the video continues where it stopped.
- **MED-002-R10**: Decoded pictures MUST wait in a queue of at most 3 pictures. The decoder MUST stop
  when the queue is full and continue when a picture is taken. Pictures whose time has passed before
  they were shown MUST be dropped (counted), never shown late or queued without bound. When playback
  time runs more than 1 second ahead of the decoder, the decoder MUST jump to the playback time
  instead of decoding everything in between.
- **MED-002-R11**: At the end of the video, playback MUST start again from the beginning (loop the
  whole video) with the timeline continuing (no gap, no frozen picture). Loop regions are MED-003.
- **MED-002-R12**: The video layer MUST follow the CMP-001 layer contract: the whole picture per
  frame in linear light, premultiplied alpha (opaque video: alpha 1), converted from the video's
  display-encoded colors, upright by the video's rotation, scaled to fill the output keeping its
  aspect ratio and cropping the overflow equally. Until a picture is ready, or after a failure, the
  layer MUST show its transparent fallback (never a stall). Per frame the layer MUST NOT decode,
  wait on a lock without bound or do I/O.
- **MED-002-R13**: Decoding MUST stop while the Video visual is not shown, while it is paused (once
  the queue is full) and in the background (the decoder is released and its pictures freed); it
  resumes at the stored playback time.
- **MED-002-R14**: Every refused import, a failed save and a stored copy that cannot be decoded MUST
  show a non-blocking notice naming the reason in plain words; the visual and the audio source keep
  running and nothing is restarted.
- **MED-002-R15**: Video reading MUST sit behind one replaceable decoder boundary with typed errors,
  so MED-014 (safe media decoder) can harden it, and MED-003 to MED-005 can change what is read,
  without changing the queue, the layer or the app.
- **MED-002-R16**: The video's own soundtrack MUST NOT be played or analysed; the visualizer's audio
  source stays the one the viewer chose.
- **MED-002-R17**: The import and the video MUST stay on the device: no upload, no network use
  (FR-068). The copy lives in the app's Application Support folder and, like other app data, is
  included in the user's own device backups.
- **MED-002-R18**: A stored identifier MUST resolve only to a file inside the app's video folder; an
  invalid identifier or a missing file reads as "no video" and is cleared. A copy that exists but
  cannot be decoded keeps its identifier, shows the transparent fallback and the notice, and can be
  removed.
- **MED-002-R19**: VoiceOver MUST name the visual ("Video visualization") and its state (no video,
  loading, playing with its size, could not be played); the Settings buttons MUST be labeled.
- **MED-002-R20**: The flows MUST be testable without the system pickers: a debug-only launch flag
  imports a generated fixture video through the same import path; it MUST NOT exist in Release
  builds.
- **MED-002-R21**: The privacy policy and the App Privacy notes MUST describe imported videos: copied
  into the app on the device without soundtrack or metadata, never sent, removable in the app,
  deleted with the app; the App Privacy answer stays "Data Not Collected".
- **MED-002-R22**: The limits, errors, playback clock and queue MUST build on every host including
  Linux; only video reading (AVFoundation) and drawing (Metal) compile out there.

### Key Entities

- **Stored video**: the app's one imported video: an identifier and the stored copy (video pictures
  and timing only), plus its size, rotation, frame rate and length read from the copy.
- **Import limits**: 500 MB per picked file, at most 4096 pixels on the longest side, at most 60
  frames per second, H.264 or HEVC.
- **Import error**: not a video, too large, unsupported codec, picture too large, frame rate too
  high, damaged, could not be read, could not be saved.
- **Playback clock**: the playback time on the video's (looping) timeline, advanced by display time.
- **Decode queue**: at most 3 decoded pictures, with counts of pictures decoded, shown and dropped
  and the deepest the queue has been.
- **Video layer**: a CMP-001 layer drawing the picture for the playback time, or throwing "not
  ready" so the compositor shows its transparent fallback; its state is empty, loading, playing
  (size) or failed (reason).

## Privacy review *(mandatory for new stored user data — Constitution, Privacy)*

| Question | Answer |
|---|---|
| What is accessed? | Only the one video the viewer picks, through the system Photos picker (out of process; no library permission) or the system Files picker (one file, read once). |
| When? | Only after the viewer taps Choose from Photos… or Choose from Files…; nothing at launch. |
| What is stored? | One copy of the video's pictures and timing, without soundtrack or metadata (no location, date, device), and its identifier in the app's settings (R3, R4, R6). No thumbnail, history or original file name. |
| What is read from the file? | Only what playback needs: the codec, picture size, rotation, frame rate and length (R5). The original's metadata is never read. |
| Where, and for how long? | In the app's Application Support folder on the device until the viewer taps Remove Video, imports another video, or deletes the app. Included in the viewer's own device backups like other app data (R17). |
| Is anything sent? | No. No upload, no network use (FR-068). |
| Is anything analysed? | No. The pictures are only scaled and drawn; the soundtrack is dropped, never played or analysed (R16). |
| What if the viewer refuses? | Nothing changes: no permission exists to refuse; cancelling a picker leaves the app as it was. |
| App Store privacy label | Unchanged: Data Not Collected. The owner confirms the answers in App Store Connect; this feature only documents them. |

Result: no collection, no transmission, no new permission; the only new stored data is the
viewer's chosen video, stripped of soundtrack and metadata and removable in the app. The review
passes, conditional on R2 to R7 and R17 being verified (MED-002-S3 to S6) and on the device tasks.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MED-002-S1**: Intended rate: with a fixture of 30 frames per second whose every picture encodes
  its own index, at playback times t over two loops the shown picture is frame ⌊t × 30⌋ mod 60 in
  100 % of samples (fake clock, no wall-clock timing).
- **MED-002-S2**: Bounded queue: the deepest the decode queue has been never exceeds 3 pictures
  across normal playback, a 5-second stall, a 10-second jump ahead, a pause and a stop; pictures
  passed over are counted as dropped and none is shown after its time.
- **MED-002-S3**: Colors: a solid fixture picture reads back within 1/255 of its expected linear
  value in a 64 × 64 layer picture (allowing for the codec's own rounding, stated in the plan).
- **MED-002-S4**: After a relaunch the same stored copy plays with no new choice, and its shown frame
  index advances (UI test).
- **MED-002-S5**: A stored copy made from a fixture with a location, a creation date and a
  soundtrack has no audio track and none of those metadata values, and none of the original's
  metadata strings appear anywhere in the stored bytes.
- **MED-002-S6**: Remove Video deletes the copy and its identifier; the next frame shows no video.
- **MED-002-S7**: 100 % of corrupt, truncated, non-video and over-limit fixtures are refused with
  their typed reason; a copy that fails while playing gives the transparent fallback and a typed
  error, and the compositor keeps drawing.
- **MED-002-S8**: The compliance check passes, the app declares no photo library usage description,
  and the built app's privacy manifest check finds no undeclared required-reason API.

## Assumptions

- One video at a time is enough for this row; in/out points are MED-003, speed MED-004, reverse
  MED-005, relinking MED-013 and the hardened decoder MED-014.
- Looping the whole video is the natural behaviour of a background video; MED-003 replaces "the whole
  video" with a saved region.
- 500 MB holds several minutes of 4K60 HEVC from an iPhone; 4096 pixels covers 4K (DCI and UHD);
  60 frames per second matches the display rate most devices sustain for a background layer.
- The layer's opacity, blend and transform come from CMP-003 to CMP-005; this row composites at the
  identity values.
- Device behaviour (Photos and Files picks, HEVC and H.264, 4K60 and long files, thermal state over
  3 minutes on D1 and D3) is verified only in the device stage, by the owner, because system
  pickers cannot be automated and simulator results are never device evidence.
