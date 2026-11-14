# Research: REC-004 Recording audio mux

## REC-004-D1 Where the recorded audio comes from

- **Decision**: a recording tap inside `NormalizedPCMRing`: a third SPSC ring (0.5 s, preallocated) written only while armed, beside projectM's ring and the analysis tap. `reset()` and `resetForHandoff()` (a new capture session: start, restart, source switch) disarm it before any sample of the new session is written; `discardBuffered()` (a seek) drains it and keeps it armed.
- **Rationale**: the normalized ring's `write` is the one place every source's audio passes, already converted to 44.1 kHz stereo; disarming at the session boundary is airtight (the producer itself stops), so a source switch can never leak the new source's audio into a recording even before the main actor notices. Input trim, noise gate and latency offset act on readers of the analysis tap, so the recorded audio is the source as captured (REC-004-R12).
- **Alternatives**: reading projectM's ring (it has one consumer and a freshness rule that skips audio); the analysis tap (one consumer: the analysis worker); a tap in each source (three paths, three formats, the mic and file paths duplicated).

## REC-004-D2 Timestamps on the same clock as the video

- **Decision**: each tap write stores, in one `Atomic<WordPair>`, the frames written since arming and the uptime-clock time of the write (`MonotonicClock`, `CLOCK_UPTIME_RAW`). The consumer loads the stamp, drains everything buffered, loads the stamp again: when no write happened in between, the last frame read was written at the stamp's time, so the chunk's first sample is at `time − (frames − 1)/44,100`. When a write raced the drain, the later stamp is used (error at most one write, about 10 ms, absorbed by D3).
- **Rationale**: the display link's `targetTimestamp` (the video's frame times) is on the same uptime clock as `mach_absolute_time`/`CLOCK_UPTIME_RAW`; the double-word atomic keeps count and time consistent without a lock (Constitution VII).
- **Alternatives**: a per-write stamp queue (more state for no gain); stamping on the consumer (adds the frame interval's jitter to every chunk).

## REC-004-D3 Placing audio in the file

- **Decision**: `RecordingAudioTimeline`: positions in samples at 44.1 kHz from the first video frame (the video's origin). The first chunk anchors at its own time; later chunks continue contiguously while their own time is within ±100 ms of the expected position; beyond that the track re-anchors (an overlap is trimmed, a gap is left empty, never padded). Samples before the origin are trimmed; `endSession` at the video's end trims anything after it. After `end()` nothing more is placed.
- **Rationale**: contiguous audio has no clicks from stamp jitter; real discontinuities (stall, underrun, seek) still land at the right time. With exact stamps (the fixture) the alignment error is below one sample plus the encoder's rounding.
- **Tolerance**: 20 ms in the file between a sound and the frame stamped at the same host time (REC-004-R6, S1). 20 ms < one 30 fps frame (33 ms) and < one AAC frame (23 ms).

## REC-004-D4 Encoding

- **Decision**: a second `AVAssetWriterInput` (`.audio`, AAC-LC `kAudioFormatMPEG4AAC`, 44,100 Hz, 2 channels, 128,000 b/s), added before `startWriting` only when the decision is "include". Chunks become LPCM Float32 interleaved `CMSampleBuffer`s with presentation time `CMTime(sample, 44_100)`; appended on the writer's serial queue. Live: a not-ready input drops the chunk and counts it (never waits). Offline (tests): waits like the video path. The track's priming is written by AVFoundation, and `AVAssetReader` removes it on read.
- **Rationale**: one writer, one file (REC-003 layout); the queue keeps audio and video appends ordered.

## REC-004-D5 Policy (ADR-0051)

- In-App Playback included; Microphone included only with permission granted and the setting on; System/App Capture never; nothing else. Decided at Record; the file has an audio track only for "include". Any switch, stop, consent change or tap disarm ends audio for that recording; no silence is inserted and no track is added later.
- DRM: In-App Playback plays only library files; `AVAudioFileInspector` refuses `hasProtectedContent` at import (CaptureKit `AudioFileInspector.swift`), decoding uses `AVAudioFile` (cannot open FairPlay content); the app has no `AVPlayer`/media-library playback path (verified by grep at audit time). No record-time DRM check is added because nothing protected can reach the tap through these sources.
- Microphone consent setting: device-local, off by default, excluded from the library backup (a consent must not travel to another device), erased with the Settings category alongside the other device switches (OSC, MIDI).

## REC-004-D6 Status and announcements

- Texts from `RecordingAudioDecision.statusText`. Before recording: the Record control's VoiceOver hint and Settings → Recording. While recording: a line under the recording indicator. Announcements go through the status-event router (new rows for "audio at start" and "audio ended"), kind `.recording`, so `check_status_events.py` stays green.

## REC-004-D7 Fixture

- Host test on the Mac (Metal device): 160 × 120 recording, offline writer, 30 fps frames from injected nanoseconds (origin 5 s), black except the frame at 1.0 s (white). Audio: silence in 441-frame chunks stamped on the same base, with a 2 ms full-scale click starting at 1.0 s. Chunks and frames are offered in time order. Read-back: decode video to BGRA, the first frame with mean > 128 gives the flash time; decode audio to Float32, the first sample above 0.3 gives the click time. Assert |click − flash| ≤ 20 ms.
