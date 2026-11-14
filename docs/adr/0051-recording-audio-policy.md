# ADR-0051: Recordings Contain Only Owned or Consented Audio, Decided at Record

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: REC-004 (`specs/134-rec-004-recording-audio`)
- **Constitution**: I (public APIs, no DRM or protected-content circumvention), IV (truthful labeling),
  V (no universal-capture claims), VII (real-time safety), X (evidence); Privacy ("audio is not
  recorded to disk by default; such a feature needs its own specification and privacy review")
- **Amends**: ADR-0027 (REC-003: every recording is video only, no audio track)

## Context

The roadmap row asks recordings to "include only audio that the app owns or is legally permitted to
capture", with the acceptance "owned audio fixture aligns within documented A/V tolerance; mic consent
respected". The app has three sources: In-App Playback (files the user imported into the app's own
library), Microphone (system permission, FR-005 explainer) and System/App Capture (other apps' audio
through ScreenCaptureKit). REC-003 wrote video only.

## Decision

1. **Sources** (`RecordingAudioPolicy`): In-App Playback audio is included. Microphone audio is
   included only when the system permission is granted **and** the new device-local setting "Include
   microphone audio" (Settings → Recording, off by default) is on. System/App Capture audio is never
   included, in any build or setting. No source, no audio.
2. **No protected audio**: In-App Playback plays only library files; the import refuses protected
   content (`AVAudioFileInspector`: `hasProtectedContent` → `protectedContent`) and decoding uses
   `AVAudioFile`, which cannot open FairPlay content. The app has no `AVPlayer`,
   `MPMusicPlayerController` or media-library playback path (grep at implementation time, 2026-11-14:
   none in `Packages/CaptureKit` or `Apps/projectM-iOS`). Apple Music items cannot enter the library. No
   record-time DRM check is added because nothing protected can reach the recording tap through the
   permitted sources, and the recorder accepts audio only through that tap.
3. **Decided at Record**: the decision fixes the file's tracks. Only "include" adds the AAC input
   (AAC-LC, 44.1 kHz stereo, 128 kb/s) and arms the normalized ring's recording tap. A recording that
   starts without permitted audio stays video only.
4. **Early end, never padded**: a change of source mode, a new capture session (the ring disarms the
   tap itself in `reset()`/`resetForHandoff()`, before the new session's first sample), or withdrawing
   the microphone consent ends the audio for good in that recording; the video goes on. No silence is
   inserted and no track is added later. A recording with "include" that receives no audio has no
   audio track (AVFoundation omits the empty input; tested). A file never has a silent track that
   suggests it had sound.
5. **Timing**: audio is dated on the uptime clock (the display link's clock) when it enters the
   normalized ring and placed in samples from the first video frame; contiguous within ±100 ms,
   re-anchored beyond. Tolerance: a sound and a frame stamped at the same host time are at most 20 ms
   apart in the file (fixture `RecordingAudioMuxTests.testOwnedAudioClickAlignsWithFlash`). The
   device's own capture delay is measured in the device stage (REC-004-S5, 40 ms).
6. **Recorded audio is the source as captured**: the normalized audio before input trim, noise gate
   and latency offset (those shape the visuals, not the music).
7. **The consent is device-local**: `settings.recording.includeMicrophone` is excluded from the library
   backup (a consent must not travel to another device), erased with the Settings category like the OSC
   and MIDI switches, and listed in the device test's allowed keys.
8. **Disclosure**: the audio status is named before recording (the Record control's VoiceOver hint,
   Settings → Recording) and during it (a line under the recording indicator); VoiceOver hears it at
   start (status event X9a) and when the audio ends early (X9b). The privacy policy says what
   recordings contain. The microphone usage description is unchanged: FR-019 keeps it identical to the
   Microphone explainer, it stays accurate (the microphone is used only in Microphone mode), and the
   separate in-app opt-in is the point-of-use disclosure for writing it into a file.

## Privacy review (Constitution, Privacy)

- **What reaches disk**: only the audio of a recording the user started with Record, in the app's
  temporary `Recordings` folder, inside the same MP4 as the video.
- **For how long**: until the user saves it with the system file mover (then it is the user's file),
  shares it, or discards it; leftovers are deleted at the next launch (REC-003-R13). Nothing is kept
  by the app after the session.
- **By default**: In-App Playback audio is included because the user explicitly pressed Record on
  music they imported themselves; the status says so before and during recording. Microphone audio
  needs both the permission and a separate opt-in that is off by default. Other apps' audio: never.
- **Nothing is sent**: no network path is added (`check_compliance.py`, `check_network_symbols`).

## Consequences

- REC-003's "no audio track" scenario now holds for System/App Capture, Microphone without consent and
  recordings without a source; In-App Playback recordings have sound.
- The normalized ring writes a third ring while armed (one copy, one atomic store per write on the
  analysis queue; nothing in audio callbacks).
- Device alignment (REC-004-T19) stays `{device}` until measured on D1.

## Alternatives rejected

- **Mux System/App Capture audio when not protected**: iOS gives no reliable per-buffer protection
  flag, and other apps' audio is not the app's to redistribute (Constitution I, V).
- **Pad with silence after a switch or for a no-audio recording**: suggests the recording had sound.
- **Add or resume an audio track after a switch back**: tracks are fixed when writing starts; resuming
  would splice two sources' audio with an arbitrary gap.
- **A tap in each source**: three formats and paths; the normalized ring is the one place all audio passes.
