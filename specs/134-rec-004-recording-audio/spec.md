# Feature Specification: REC-004 Recording audio mux

**Feature Branch**: `feature/rec-004` (spec directory `134-rec-004-recording-audio`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement REC-004 (Recording audio mux) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Include only audio that the app owns or is legally permitted to
capture." Acceptance, verbatim: "Owned audio fixture aligns within documented A/V tolerance; mic
consent respected." Verification: fixture encoding plus the simulator; device in the last stage.
P1, L, depends on REC-003 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `REC-004-R1…`, success criteria `REC-004-S1…`, tasks `REC-004-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `e8dde5c0`)

| Area | Today |
|---|---|
| Video recording | REC-003 (ADR-0027): `MetalFrameRecorder` writes shown frames of the Camera, Photo, Video, Text and spectrum visuals into an MP4 through one `AVAssetWriter` video input (HEVC, then H.264). Frame times are the frame loop's presentation times (display-link target timestamps, nanoseconds on the host uptime clock); the first frame is time 0, later frames are rounded to 1/600 s. The writer has no audio input: every file is video only (REC-003 Story 2 scenario 4). projectM is not recordable. |
| Controls and files | REC-003/REC-012/REC-015: the Record control, the elapsed-time indicator, stop reasons with notices, the "Recording ready" offer (Save…, Share…, Discard) and the disk guard. Files exist only in `<tmp>/Recordings` until the user saves them. |
| Audio sources | CaptureKit: In-App Playback (files the user imported into the app's library, decoded with the system file decoder; imports refuse DRM-protected files, `AudioFileInspector` → `protectedContent`), Microphone (needs the system microphone permission, asked at first use after an explanation, FILE-013 catalog), System/App Capture (other apps' audio through ScreenCaptureKit, iOS 27+). |
| Normalized audio | AudioCore: every source's audio is converted to Float32 stereo 44.1 kHz and written to one normalized ring (projectM's reader with a 50 ms freshness rule) plus an optional analysis tap. The ring keeps no timestamps. |
| Clock | Sources stamp buffers with host times; `MonotonicClock` is the uptime clock, the same clock as the display link's timestamps. |
| Constitution | Principle I: never circumvent DRM, protected-content exclusion or app capture restrictions. Privacy: audio is not recorded to disk by default; any such feature needs its own specification and privacy review (this one). |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Which audio sources may be written into a recording? → A: In-App Playback audio (files the user imported into the app's own library; the app owns and decodes them) is included. Microphone audio is included only when the system microphone permission is granted **and** the user has turned on the new "Include microphone audio" recording setting (off by default). System/App Capture audio (other apps' audio) is never included: it may be protected and it is not the app's to redistribute; the recording is then video only and says so.
- Q: Can protected (DRM) audio reach a recording? → A: No. The In-App Playback path decodes only files that passed the import check, which refuses protected content, and plays them with the system file decoder (no streaming player, no FairPlay key path). Apple Music items cannot enter the library. The recorder accepts audio only from the In-App Playback and Microphone sources, so nothing else can be muxed whatever its origin.
- Q: What does a recording with no permitted audio contain? → A: No audio track at all. The app never writes a silent track that would suggest the recording had sound.
- Q: What happens when the source changes during a recording? → A: The audio track ends at the switch and does not resume in that recording, whatever the new source is; the video goes on. No silence is inserted. The same happens when the user turns "Include microphone audio" off while recording the microphone, or the source stops. A recording that started without a permitted source stays video only even if a permitted source starts later (the file's tracks are fixed when it starts).
- Q: What A/V tolerance is promised? → A: In the written file, a sound and the frame stamped at the same host time are at most 20 ms apart (less than one frame at 30 fps, about one AAC frame of 1,024 samples at 44.1 kHz is 23 ms; 20 ms is the stricter bound). This is measured by the fixture with injected times; the device's own pipeline delay is measured in the last stage.
- Q: How is the audio encoded? → A: AAC-LC, 44.1 kHz stereo, 128 kb/s, in the same MP4 as the video, no metadata.
- Q: How does the user know what audio a recording holds? → A: An audio status text (where it appears: see the speckit-clarify session) says what the next or current recording contains ("Recording includes app audio.", "Recording includes microphone audio.", "Recording has no audio: other apps' audio is never recorded.", "Recording has no audio: Include microphone audio is off.", "Recording has no audio: microphone permission is off.", "Recording has no audio."), and VoiceOver announces the audio status when a recording starts and when its audio ends early.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Which version of the audio goes into the file: as captured, or after the user's input trim, noise gate and latency offset? → A: As captured: the normalized source audio (44.1 kHz stereo) before input trim, noise gate and the renderer's latency offset. Those settings shape what drives the visuals; a recording should sound like the music, and the latency offset compensates for the screen, which a file does not need. The AUD-012 switch fade is part of the normalized audio and stays.
- Q: Where does the user find "Include microphone audio"? → A: In Settings, in a new "Recording" section (the toggle plus one line of explanation), not in the visualizer controls, which keep only the audio status. A second place would need its own VoiceOver review.
- Q: When and where is the audio status shown? → A: Before a recording, as the Record control's VoiceOver hint and in Settings → Recording (what the next recording would contain, from the current source and setting); during a recording, as a visible line under the recording indicator (the decision made at Record, or "Recording audio ended." after an early end). The controls grid keeps its one-line buttons; a second visible line there would crowd the wrapping grid.
- Q: Can the setting change during a recording? → A: Yes. Turning it off while the microphone is being recorded ends the audio at once (REC-004-R5). Turning it on during a recording does not add audio to that recording (its tracks are fixed at Record); the next recording includes it.
- Q: What if the microphone permission is undetermined when the user turns the setting on? → A: The setting does not ask for permission; the permission is asked only by Microphone mode at its point of use (FILE-013). The setting's footer says microphone audio needs the permission, and the audio status says "Recording has no audio: microphone permission is off." when it is missing.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Recordings of the app's own music have sound in sync (Priority: P1)

A user plays a song from the app's library and records the visualizer; the saved video has the song
in sync with the picture.

**Why this priority**: It is the row's acceptance criterion and the main value of the feature.

**Independent Test**: Fixture encoding: synthetic video frames with a white flash at a known time and
owned audio with a click at the same host time are recorded with injected timestamps, then read back:
the click and the flash are at most 20 ms apart.

**Acceptance Scenarios**:

1. **Given** In-App Playback is the source and a recordable visual is shown, **When** the user records, **Then** the file has one video track and one AAC audio track.
2. **Given** the fixture (flash and click at the same host time), **When** the file is read back, **Then** the click's time and the flash frame's time differ by at most 20 ms.
3. **Given** audio arrives before the first video frame, **When** the file is written, **Then** audio earlier than the first frame is left out (the file starts with the first frame).

---

### User Story 2 - Microphone audio only with consent (Priority: P1)

A user who wants the room's sound in a recording turns on "Include microphone audio"; without that
setting, or without the system permission, the microphone is never in a recording.

**Why this priority**: The acceptance names microphone consent; recording a room is sensitive.

**Independent Test**: Recorder and policy tests with a stubbed permission: setting off or permission
denied gives a file with no audio track although microphone samples were offered; setting on and
permission granted gives a track with the samples.

**Acceptance Scenarios**:

1. **Given** Microphone is the source and the setting is off, **When** the user records, **Then** the file has no audio track and the audio status says why.
2. **Given** the setting is on and the permission is denied or undetermined, **When** the user records, **Then** the file has no audio track.
3. **Given** the setting is on and the permission is granted, **When** the user records, **Then** the file holds the microphone audio.
4. **Given** a new install, **When** the user opens Settings, **Then** "Include microphone audio" is off.

---

### User Story 3 - Other apps' audio is never recorded (Priority: P1)

A user visualizing another app's audio through System/App Capture records the visualizer; the file is
video only, and the app says so before and during recording.

**Why this priority**: The constitution forbids circumventing protected-content exclusion; other
apps' audio may be protected.

**Independent Test**: Policy and recorder tests: with System/App Capture as the source the decision is
"exclude" and the file has no audio track even when audio is offered.

**Acceptance Scenarios**:

1. **Given** System/App Capture is the source, **When** the user records, **Then** the file has no audio track and the audio status says other apps' audio is never recorded.
2. **Given** a recording with app audio runs, **When** the source switches to System/App Capture, **Then** the audio track ends at the switch (within 20 ms) and nothing after it has audio.

---

### User Story 4 - Know what the recording contains (Priority: P2)

The Record area shows which audio the recording contains; VoiceOver users hear it.

**Independent Test**: An app UI test toggles "Include microphone audio" in Settings and reads the
setting's value; app unit tests check the status texts and the announcement for each decision.

**Acceptance Scenarios**:

1. **Given** any source, **When** the user reads the Record control with VoiceOver or opens Settings → Recording, **Then** the audio the next recording will contain is named; **When** recording, **Then** a line under the indicator names it.
2. **Given** a recording starts or its audio ends early, **When** VoiceOver runs, **Then** the audio status is announced once.

### Edge Cases

- The source stops (pause, interruption, end of the queue) during a recording: the audio track ends; the video goes on.
- A seek or track change inside In-App Playback is not a source switch: audio continues, with a re-anchor when the timing jumps.
- Audio arrives in bursts or late: samples are placed by their host time; a gap or overlap above the tolerance re-anchors the track (an overlap is trimmed, a gap is left empty, never padded).
- The recording ends with fewer than two video frames: no file (REC-003), audio included.
- The writer fails while appending audio: the recording fails like a video writer failure (REC-003 notice), no partial file is kept.
- projectM is shown: Record is unavailable (REC-003); nothing here changes that.

## Requirements *(mandatory)*

### Functional Requirements

- **REC-004-R1**: A recording MUST contain audio only from In-App Playback, or from the Microphone when the permission is granted and "Include microphone audio" is on. All other cases MUST produce a file with no audio track.
- **REC-004-R2**: System/App Capture audio MUST never be written into a recording, in any build or setting.
- **REC-004-R3**: "Include microphone audio" MUST default to off and be stored on the device only. It is a consent, so it MUST be left out of the library backup (it never travels to another device), MUST be erased with the Settings category like the other device switches, and MUST be reset by the UI-test reset.
- **REC-004-R4**: The audio decision MUST be made when the recording starts; the file MUST have an audio track only if the decision is "include".
- **REC-004-R5**: When the source changes, stops, becomes non-permitted or the microphone setting is turned off during a recording, the audio MUST end at that point and MUST NOT resume in that recording; no silence MUST be inserted.
- **REC-004-R6**: Audio MUST be placed by host time on the same clock as the video frames; a sound and a frame stamped at the same host time MUST be at most 20 ms apart in the file. Audio before the first frame and after the last frame MUST be left out.
- **REC-004-R7**: Audio MUST be AAC-LC, 44.1 kHz stereo, 128 kb/s, in the same MP4, with no metadata.
- **REC-004-R8**: Audio for the recording MUST be taken without blocking the audio path or the frame loop (bounded buffers, drop-and-count on overflow), and only while a recording with audio runs.
- **REC-004-R9**: The app MUST name the audio a recording contains: before recording in the Record control's VoiceOver hint and in Settings → Recording, during recording in a visible line under the recording indicator; VoiceOver MUST announce it when recording starts and when its audio ends early, through the app's announcement lanes.
- **REC-004-R10**: Only files that passed the import check (which refuses protected content) MUST be the In-App Playback source of recorded audio; the app MUST NOT add any decryption or protected-stream path.
- **REC-004-R12**: The recorded audio MUST be the normalized source audio, before input trim, noise gate and latency offset.
- **REC-004-R13**: "Include microphone audio" MUST be in a "Recording" section of Settings; it MUST NOT request the microphone permission itself.
- **REC-004-R11**: The microphone usage description and the privacy policy MUST say that microphone audio is in recordings only when the user turns it on.

### Key Entities

- **Recording audio decision**: include (app audio or microphone audio) or exclude (with a reason: other apps' audio, microphone off, microphone permission missing, no source). Made at Record.
- **Recording audio setting**: "Include microphone audio", a device-local boolean, off by default.
- **Audio track timeline**: maps host-timed audio chunks to positions in the file relative to the first video frame; contiguous within the tolerance, re-anchored beyond it, ended for good on a switch.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **REC-004-S1**: In the owned-audio fixture, the click and the flash are at most 20 ms apart in the read-back file.
- **REC-004-S2**: With the microphone setting off or the permission missing, 0 microphone samples are in the file (no audio track); with both granted, the track is present and holds the offered samples.
- **REC-004-S3**: With System/App Capture as the source, 100% of recordings have no audio track.
- **REC-004-S4**: After a mid-recording switch to a non-permitted source, the audio track ends within 20 ms of the switch.
- **REC-004-S5**: On a device, a recording of In-App Playback plays back in sync as judged by a click-and-flash test within 40 ms (device stage, `{device}`).

## Assumptions

- The display-link target timestamps and the audio sources' host times use the same uptime clock (verified in the audit).
- The import check's protected-content refusal is the gate for owned audio; DRM detection is not repeated at record time.
- Audio pipeline delay on a device (source → normalized ring) is a few tens of milliseconds; the fixture proves the muxer's alignment, the device stage measures the whole chain.
- projectM recording, editing of recordings and per-recording audio levels are out of scope.
