# Research: REC-003 Video Recording

Decisions made under owner rule 4 (best judgement), 2026-11-13. Each lists the decision, the
rationale and the alternatives rejected. The spec's Clarifications hold the product decisions; this
file holds the technical ones.

## REC-003-D1: Writer — AVAssetWriter with a pixel-buffer adaptor, MP4

- **Decision**: `AVAssetWriter` (file type `.mp4`) with one `AVAssetWriterInput` (video) and an
  `AVAssetWriterInputPixelBufferAdaptor` whose pool makes IOSurface-backed, Metal-compatible
  32BGRA buffers at the source size. `expectsMediaDataInRealTime = true` for live recording; false
  for fixture/offline use (then the writer queue may wait for readiness; never the frame loop).
  `mediaTimeScale = 600`. `metadata = []`, `shouldOptimizeForNetworkUse = false`.
- **Rationale**: the documented way to write encoded video from pixel buffers; VideoToolbox does the
  encoding inside. MP4 opens everywhere (Files preview, Photos, other platforms).
- **Alternatives**: VideoToolbox `VTCompressionSession` + a muxer of our own (more code, no gain);
  `.mov` (fine, but less portable).

## REC-003-D2: Codec — HEVC when it can be written, else H.264

- **Decision**: try HEVC, then H.264: for each, `canApply(outputSettings:forMediaType:)`, add the
  input, `startWriting()`; on any failure delete the file and try the next. HEVC: average bit rate
  0.12 bit per pixel per frame; H.264 (High, auto level): 0.2. Key frame at least every 2 s.
  Color: Rec. 709 primaries, transfer function and matrix.
- **Rationale**: HEVC halves the size where a hardware encoder exists (all target devices); the
  simulator may not encode HEVC, and the fallback keeps every runtime working. A fixed bits-per-pixel
  rate keeps file size predictable (about 6-10 Mb/s at 1920 × 886 × 30).
- **Alternatives**: always H.264 (twice the size); querying `VTCopyVideoEncoderList` (a list of
  encoders is not a promise that the writer starts).

## REC-003-D3: Size — the drawable cropped to even, scaled by the writer to ≤ 1920

- **Decision**: source = drawable size with odd width or height reduced by one (the last column or
  row is cropped: the compositor's output pass and the blit both address pixels from the top left);
  output = source scaled to fit 1920 on the long side, rounded to even, aspect kept. The writer
  scales (`AVVideoScalingModeKey = AVVideoScalingModeResizeAspect`) when output ≠ source.
- **Rationale**: no new shader (the output pass reads by pixel, it cannot scale); hardware scaling
  inside the encoder path; chroma subsampling needs even sizes.
- **Alternatives**: an MPS or shader scale (new GPU code); recording at full size (heavier).

## REC-003-D4: Timestamps — the frame clock on a 1/600 s base, strictly increasing

- **Decision**: each frame's time is the frame loop's presentation time (`CADisplayLink`
  `targetTimestamp`, the same time the compositor's frame clock receives), relative to the first
  recorded frame, rounded to 1/600 s ticks. Rule per frame, in order: tick ≤ last written tick →
  drop (counted, "not increasing"); tick ≥ 10 min → stop (duration reached); tick − last <
  interval − interval/4 (interval = 20 ticks at 30 fps) → skip (rate cap, not a drop); else
  candidate. A candidate is written only when the gate admits it (D5); only then does it become the
  last written tick. The session ends at last tick + one interval, so a 300-frame fixture lasts
  exactly 10 s.
- **Rationale**: real presentation times keep motion honest when the loop runs slower than 30 fps
  (variable frame rate, no invented frames); 600 divides 24, 25, 30 and 60 (REC-006). The jitter
  tolerance keeps every other frame of a 60 Hz loop.
- **Alternatives**: a constant rate with counted frames (time drifts when frames are late); nanosecond
  time base (the MP4 track rounds anyway; tests could not compare exactly).

## REC-003-D5: Bounded queue — 3 frames in flight, drop when full or not ready

- **Decision**: `RecordingFrameGate` counts frames from "pixel buffer taken" to "appended or
  dropped" under a `Mutex`; at 3 it refuses and the frame is dropped (counted "encoder busy"). On
  the writer queue, a frame arriving when `isReadyForMoreMediaData` is false is dropped (counted "not
  ready") in real-time mode. The pool cannot grow beyond 3 buffers in use, plus what the encoder holds
  internally.
- **Rationale**: Constitution VII's bounded-queue rule applied to video; the frame loop never waits.
- **Alternatives**: waiting for the encoder (stalls the show); an unbounded queue (memory grows).

## REC-003-D6: GPU copy per visual, nothing on the CPU

- **Decision**: compositor visuals call `Compositor.encodeOutput(into:commandBuffer:)` (the existing
  `cmp_output` pipeline for `.bgra8Unorm_srgb`, with the flash guard's gain buffer, into the pixel
  buffer's texture) right after `composite` in the same command buffer; native spectra blit their
  drawn drawable (they keep `framebufferOnly` off while recording, as REC-001 does for one frame).
  The pixel buffer goes to the writer from the command buffer's completed handler.
- **Rationale**: the same pixels as the screen (post guard, sRGB-encoded 8-bit, alpha ignored = over
  black, as the opaque layer shows them); no read-back.
- **Alternatives**: REC-001's half-float read-back per frame (CPU conversion of 10+ MB per frame).

## REC-003-D7: projectM not recordable in this row

- **Decision**: projectM draws through ANGLE into its own surface; the only frame path is
  `glReadPixels` (a synchronous GPU stall). Record is shown unavailable for projectM with the reason;
  ADR-0027 lists the follow-up (an ANGLE-side copy into an IOSurface-backed texture shared with
  Metal, measured on devices).
- **Alternatives**: per-frame read-back at a reduced rate (unmeasured stall on the main visual).

## REC-003-D8: Lifecycle — every interruption stops and finishes

- **Decision**: the coordinator checks the context every 0.25 s while recording (and the hosts
  report size changes and failures per frame): pause, blackout or restore, visual change,
  presentation loss → stop with that reason; `didEnterBackground` → stop inside a
  `beginBackgroundTask` grant ended when the file is finished. Stopping detaches the tap first (no
  later frame is accepted), waits for frames in flight, then `endSession` + `finishWriting` on the
  writer queue. Fewer than 2 frames → no file. Writer failure → delete the file, notice.
- **Rationale**: one predictable rule (spec Clarifications); `finishWriting` needs the app running.

## REC-003-D9: Export — `fileMover`, temporary folder, no Photos

- **Decision**: the finished file in `<tmp>/Recordings/` is handed to SwiftUI's `fileMover` (moves
  the file to the user's chosen location; no copy in memory); on cancel or failure the temporary file
  is deleted; at launch the folder is emptied (directory listing only, no timestamps: no
  required-reason API). Name: "Visualizer Recording 2026-11-13 at 14.05.32.mp4".
- **Alternatives**: `fileExporter` with a `FileDocument` (copies a file of up to 1 GB through a file
  wrapper); Photos (REC-011).
