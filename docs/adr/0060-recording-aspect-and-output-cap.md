# ADR-0060: Recording Aspect Presets Crop to Fill in the Encoder's Scaler; Every Output Has a Per-Device Size Cap

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: REC-014 (`specs/215-rec-014-export-aspect-presets`)
- **Constitution**: I (public APIs), IV (truthful labeling), VII (real-time safety), X (evidence)
- **Amends**: ADR-0027 (REC-003 geometry, research REC-003-D3: the video always has the drawable's aspect
  and only scales down to the profile's long side)

## Context

REC-014 asks to "offer portrait, square, landscape and custom safe dimensions", accepted when "export
dimensions match preset and never exceed device memory cap". Under ADR-0027 a recording always had
the screen's aspect, and the only size limit was the profile's long side (none for Max) and the
encoder's own `canEncode`, which accepts 8K on recent devices.

## Decision

1. **Choices**: Match screen (default, ADR-0027 unchanged), Portrait 9:16, Square 1:1, Landscape 16:9,
   Custom W×H (each side even, 128...4096). Presets are absolute (Portrait is always taller than wide).
2. **Crop to fill, centred, in the encoder's scaler**: the pixel buffers stay the even drawable (the
   five visual hosts and the frame loop are untouched); the writer's `AVVideoScalingModeKey` is
   `AVVideoScalingModeResizeAspectFill` for every aspect but Match screen, so the picture is scaled
   uniformly to cover the output and its centre is kept. No bars, no distortion, no frame-loop work.
   Letterboxing was rejected (a landscape file from a phone would be mostly black).
3. **Exact, never upscaled sizes**: a preset's output is the largest even multiple of its ratio whose
   long side is at most the profile's, that fits the centred crop of the drawable in both dimensions
   (REC-005-R2: no upscale), and that is within the cap. A custom size is used exactly when it fits;
   otherwise it is reduced (same ratio, even sides) and Settings and Record say so (row X9c).
4. **Output cap per device class** (`RecordingOutputCap`), applied to every recording: below 4 GiB of
   physical memory at most 2560 px per side and 3 686 400 pixels; otherwise 4096 px and 8 294 400 pixels;
   never above the GPU's texture side. Every shipping screen fits its class's cap, so Match screen
   recordings are unchanged on real devices.

## Consequences

- The encoder's scaler does the crop; the host fixture checks the written size and that the centre is
  written. Device playback is `{device}` (REC-014-T15).
- Source pixel buffers stay drawable-sized (as before); only the encoded frames are capped.
- Still captures (REC-001) are unaffected.
