# ADR-0027: Video Recording Pipeline

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: REC-003 (`specs/058-rec-003-video-recording`)
- **Constitution**: I, VI, VII (bounded queues), X; Privacy
- **Builds on**: ADR-0013 (compositor), ADR-0011 (strobe safety envelope), REC-001
  (`specs/055-rec-001-still-frame-capture`)
- **Number**: 0025 and 0026 are left to the PERF-014 and MED-014 rows running in parallel.

## Context

REC-003 asks the app to "record composited frames into local video file with timestamped frames",
accepted when a "ten-second fixture decodes and preserves monotonic timestamps". It is the first
continuous output of the app's pictures; REC-004 (audio), REC-005/006 (quality, frame rate),
REC-008 (timed stop), REC-013 (offline export), REC-015 (disk guard) and REC-016 (interruption
recovery) build on it, so the pipeline's shape and limits are recorded here.

## Decisions

1. **One recorder, fed on the GPU.** `MetalFrameRecorder` (target `FrameRecording` in
   `Packages/Compositor`) owns an `AVAssetWriter` (MP4, one video input, pixel-buffer adaptor) and a
   `CVMetalTextureCache`. Per accepted frame the visual's frame loop encodes the frame as shown into
   an IOSurface-backed BGRA pixel buffer's `bgra8Unorm_srgb` texture in its own command buffer:
   compositor visuals through `Compositor.encodeOutput` (the existing output pipeline after the
   flash guard), native spectra with a blit of the drawn drawable. The buffer is appended from the
   command buffer's completed handler on the writer's serial queue. No CPU read-back, no new shader.
2. **Timestamps.** The frame loop's presentation time, relative to the first frame, on a 1/600 s
   base. Written times are strictly increasing; a frame that is not later is dropped and counted.
   At most 30 frames per second (closer frames are skipped); real times otherwise (variable rate).
   The session ends one interval after the last frame.
3. **Bounded queue.** At most 3 frames between "buffer taken" and "appended"; beyond that, or when
   the encoder is not ready, the frame is dropped and counted. The frame loop never waits. Offline
   use (tests, later REC-013) sets `realTime: false`: the writer queue then waits for the encoder,
   still never the caller.
4. **Format.** HEVC when the writer starts with it, else H.264; long side ≤ 1920 (the writer scales),
   even size, 8-bit SDR, Rec. 709 tags; no audio track; no metadata items.
5. **Scope limit: projectM is not recordable yet.** Its frames exist only in ANGLE's GL surface; the
   only path today is `glReadPixels`, a synchronous stall. Follow-up (a later REC row or REC-003
   follow-up): copy the post-pass framebuffer into an IOSurface-backed texture shared between ANGLE
   (`EGL_ANGLE_iosurface_client_buffer`) and Metal, measured on D1-D3 before it ships.
6. **Lifecycle.** Every interruption (background, pause, blackout, visual or size change,
   presentation loss, 10 minutes, writer failure) stops the recording and finishes the file; the
   background stop runs inside a background-task grant. The file goes to the system file mover;
   nothing is kept.

## Consequences

- Recording costs one render pass or blit per recorded frame plus hardware encoding; measured on
  devices by the `{device}` tasks before any performance claim.
- REC-004 adds an audio input to the same writer; REC-006 changes `maxFrameRate`; REC-005 changes the
  long-side cap and bit rate; REC-015 adds a free-space estimate (a required-reason API, declared
  then; see the amendment below).
- A rotation ends the recording (size change); REC-014 (aspect presets) can render into a fixed size
  instead.

## Amendment 2026-11-13: REC-015 disk guard

Decided by Claude under the owner's best-judgement rule (owner rule 4); spec
`specs/063-rec-015-recording-disk-guard` (clarifications and research REC-015-D1 to D7). No
constitution default is overridden, so this amends the pipeline ADR instead of adding one.

7. **Free-space guard.** `FrameRecording` estimates the write rate as the highest average bit rate of
   the preferred codecs at the output size and frame rate, plus 25%. Record reads the volume's
   "available capacity for important usage" once (after the other refusals) and refuses below a
   200 MiB reserve plus 60 s at that rate. While recording, the app reads it and the file's size
   every 5 s off the main actor (never on the frame loop or the writer queue) and stops with the new
   reason `lowStorage` when less than the reserve plus two intervals at the larger of the estimated
   and measured rates remains; that stop finishes and offers the file like every other stop. An
   unreadable value never refuses or stops.
8. **Out-of-space failures.** Writer errors whose domain/code (or any underlying error's) is Cocoa
   640, AVFoundation -11807 or POSIX 28 become `RecordingFailure.storageFull` ("Storage is full; the
   recording couldn't be saved."); the partial file is deleted (an `AVAssetWriter` in `.failed`
   cannot finish a file), so no broken file is ever offered.
9. **Privacy.** The free-space read is a required-reason API (Disk space), declared in the app's
   privacy manifest with E174.1; the value is used only on the device and never stored or sent.
   `check_privacy_manifest.py` now also checks each declared reason against an allowed set per
   category.
10. **Test seams.** `StorageProbe` (injected readings) and `RecordingWriterFault` (the writer fails
    after N frames with an injected error); DEBUG `-uitestStorage low|dropAfter:<n>` in the app.
