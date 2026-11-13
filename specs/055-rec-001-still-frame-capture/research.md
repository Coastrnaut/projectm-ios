# Research: REC-001 Still Frame Capture

Decisions use the IDs `REC-001-D1…`. Clarifications in the spec record the product decisions; this
file records the technical ones.

## REC-001-D1: Capture point per renderer

- **Decision**: capture the frame each visual presents next, after its own flash limiting:
  - CMP-001 compositor: a second output pass into a private `rgba16Float` texture with the same
    `cmp_output` pipeline (composite × the flash guard's gain buffer), then a blit into a shared
    `MTLBuffer`, delivered from the command buffer's completed handler. The guard's gain is computed
    on the GPU in the same command buffer before both output passes, so the two passes see the same
    gain.
  - Native spectra: `CAMetalLayer.framebufferOnly` is set to false while a request is pending; the
    first drawable whose texture reports `isFramebufferOnly == false` is blitted after it is drawn;
    then `framebufferOnly` returns to true. The generator and bloom already include Reduce flashing.
  - projectM: `glReadPixels` of framebuffer 0 after `PMFlashLimiterFinish` and before
    `eglSwapBuffers` (ANGLE's swap behavior is "destroyed", so after the swap the buffer is
    undefined). The existing test readback (`PMANGLEReadPixelsRGBA`) is reused.
- **Rationale**: one rule ("what was shown"), no second render of the scene (no doubled flash
  history or animation step), no new shader (SHD-011 allowlist unchanged), no change to frames
  without a request.
- **Alternatives**: re-composite into an offscreen target (advances the frame clock and flash
  history twice); always `framebufferOnly = false` (a permanent bandwidth cost for a rare action);
  read the drawable for the compositor too (8-bit premultiplied sRGB loses precision when
  unpremultiplying; the half-float composite is exact); a screen snapshot API (captures UI, not the
  visual, and not the external display).

## REC-001-D2: Storage modes on the simulator and devices

- **Decision**: render targets stay `.private`; readback always goes through a blit into a
  `.shared` `MTLBuffer` (rows tightly packed: `width × bytesPerPixel`).
- **Rationale**: Simulator Metal does not allow shared textures; buffers are shared everywhere.

## REC-001-D3: Color conversion

- Half float decoded by bits (no `Float16` type: unavailable on some hosts).
- Linear premultiplied input: `a = clamp(a, 0, 1)`, `rgb = clamp(rgb, 0, a)`.
  - Opaque (HEIF, or PNG of a frame with no coverage below 1): written color = `rgb` (premultiplied
    over black), alpha dropped.
  - Straight (PNG with alpha): `a8 = round(a × 255)`; if `a8 == 0` the pixel is (0, 0, 0, 0);
    otherwise color = `min(rgb / a, 1)`.
  - Then sRGB: `c ≤ 0.0031308 ? 12.92c : 1.055 c^(1/2.4) − 0.055`, `round(c × 255)`.
  - "Any coverage below 1" is decided on `a8 < 255` (the stored value), so a PNG has alpha exactly
    when a stored alpha would differ from 255.
- 8-bit sRGB inputs (native BGRA, projectM RGBA) are already display-encoded: channels are swizzled,
  rows flipped (projectM), alpha set to 255; no re-encoding.
- **Rationale**: the bgra8Unorm_srgb drawable shows `sRGB(premultiplied rgb)` on an opaque layer,
  which is exactly the opaque rule; the straight rule over black reproduces it.

## REC-001-D4: Encoding

- ImageIO `CGImageDestination` with `public.png` / `public.heic`, a `CGImage` in `CGColorSpace.sRGB`
  (8 bits per component, `premultipliedLast`-free: `last` for straight alpha, `noneSkipLast` without).
  HEIF: `kCGImageDestinationLossyCompressionQuality = 0.9`. No other properties are passed.
- HEIF availability: `CGImageDestinationCopyTypeIdentifiers()` contains `public.heic`; otherwise
  HEIF is not offered.
- Tolerances: PNG exact (±1/255 to allow rounding); HEIF ±12/255 per channel on flat regions of the
  64 × 48 fixture (chroma subsampling blurs edges; tests sample region centers).

## REC-001-D5: Metadata

- The written files contain only what ImageIO derives from the image: dimensions, color model, depth,
  alpha flag, and the sRGB profile. ImageIO also writes an `{Exif}` dictionary describing the image
  itself (`ColorSpace`, `PixelXDimension`, `PixelYDimension`); the tests allow exactly those keys and
  refuse `{GPS}`, `{IPTC}`, `{MakerApple}`, any other Exif key (dates, camera, lens), `{TIFF}`
  Make/Model/Software/DateTime/Artist/HostComputer and PNG text chunks.

## REC-001-D6: Timeout and cancellation

- A request waits for at most 1 s (an injected `Duration` in tests) for the frame; a visual change,
  presentation loss or pause cancels it. The coordinator compares a request token, so a late
  frame from a cancelled request is dropped.

## REC-001-D7: Files exporter

- SwiftUI `fileExporter(isPresented:document:contentType:defaultFilename:onCompletion:)` with a
  `FileDocument` holding the bytes. The document is cleared when the sheet completes or is
  cancelled. DEBUG `-uitestCaptureDirectory <name>` writes `<tmp>/<name>/<file>` instead and the probe
  reports `format width×height alpha|opaque` (read back with the same inspector).

## REC-001-D8: External display and blackout

- The visual host's view lives in one slot (OUT-001); its drawable is the external display's size
  while it is there, so capture is automatically from the output the visual is on. Blackout's cover
  sits above the visual and is not part of the drawable, which is why capture is refused while the
  blackout is not live (spec Clarifications).

## Follow-ups for later REC rows

- REC-003 (video) can reuse `requestFrameCapture` per frame only with a pooled, ring-buffered
  readback; REC-001's one-shot allocation is deliberately simple.
- REC-011 adds Photos export (its own permission and privacy review); REC-012 the share sheet.
