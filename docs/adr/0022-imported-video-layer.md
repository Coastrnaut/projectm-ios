# ADR-0022: Imported Video Layer

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: MED-002 (`specs/048-med-002-import-video-layer`)
- **Constitution**: I, VI, VII, X; Security (imported files are untrusted); Privacy

## Context

MED-002 plays a video the user picks as a layer: "Video plays at intended rate with bounded decode
queue." MED-001 (ADR-0020) set the pattern for imported media (out-of-process pickers, a sanitized
copy in Application Support, typed errors, a decoder seam for MED-014). Video adds time: pictures
must be paced to the file's own timeline from the compositor's clock, memory must stay bounded
whatever the display does, and the file carries a soundtrack and richer metadata. Later rows build
on it: loop regions (MED-003), speed (MED-004), reverse (MED-005), relinking (MED-013), the hardened
decoder (MED-014).

## Decisions

1. **Decoder: `AVAssetReader`, pulled on a dedicated decode thread** (not `AVPlayerItemVideoOutput`).
   It decodes only when asked and returns each picture with its exact timestamp, so the queue bound
   is hard and the frame for a time is testable with an injected clock. `AVPlayer`'s clock is wall
   time and its buffering is its own. Output 32BGRA converted to BT.709 R′G′B′ (HDR and P3 videos are
   shown in standard range), wrapped without a copy by `CVMetalTextureCache` as `.bgra8Unorm_srgb`
   (linear light in the shader), alpha 1.
2. **Bounded decode queue of 3.** A counting semaphore holds one permit per free slot; the decode
   thread takes one before each picture and sleeps while the queue is full (a paused visual costs
   no CPU). The render side never waits (`NSLock.try()`). Pictures whose time has passed are dropped
   and counted, never shown late; a newer due picture replaces older due ones in the queue so the
   decoder catches up after a hitch; more than 1 s behind, the decoder seeks instead.
3. **Timing.** A playback clock advances by the difference of the compositor's presentation times
   (intended rate, 1×, kept through hitches up to 1 s); a gap over 1 s (pause, background) adds
   nothing, so the video continues where it stopped. At playback time t the layer shows the latest
   picture with timestamp ≤ t. The timeline is unwrapped (`loop × duration + pts`): at the end of
   the file the whole video loops without a gap (MED-003 adds regions). Pause leaves the decoder
   asleep; background, scene and presentation loss stop it and free its pictures; it restarts at the
   same playback time. A relaunch starts at 0 (the position is not stored).
4. **Import: remux, not re-encode, not the original.** The checked file's video track goes into an
   empty `AVMutableComposition` (rotation kept) exported with the passthrough preset and no
   metadata: the stored `.mov` has the pictures and timing only — no soundtrack, no location, date,
   device or other metadata — at the original quality, for the cost of a file copy.
5. **Limits and errors.** 500 MB file, H.264 or HEVC, ≤ 4096 px longest side, ≤ 60 fps nominal
   (60.5 accepted for rounding), the first picture must decode; typed `VideoImportError`s with plain
   notices. `VideoFrameReading` is the seam MED-014 hardens and MED-003 to MED-005 read through.
6. **No video audio.** The video's soundtrack is neither played nor analysed nor stored; the
   visualizer's audio source stays the user's chosen source (Constitution VII untouched).
7. **The app shows one fixed stack**: Settings › Visual › "Video" = video layer with the circular
   spectrum on top, persisted like Photo, in `VideoVisualHost` (Photo's loop rules plus decoder
   suspension). One video at a time in `Application Support/Videos/<UUID>.mov`, identifier
   `settings.video.id`, resolved only inside that folder, removable. `VideoLayer` reuses
   `CameraLayer`'s rotation and aspect-fill geometry.

## Consequences

- App Privacy stays "Data Not Collected"; the privacy policy describes imported videos.
- `VideoVisualHost`, `VideoStore` and `VideoCoordinator` repeat the Photo files; a shared media host
  is left to the scene rows.
- After a hitch shorter than 1 s the first frame may still show an older decoded picture (never a
  later one); the following frames are exact.
- Device behaviour (real pickers, HEVC from the camera, 4K60, long files, thermal state over 3 min)
  is verified by the owner on D1 and D3 (MED-002-T26 to T28).
