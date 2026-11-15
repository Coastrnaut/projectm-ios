# Research: MED-008 Animated Image Support

- **MED-008-D1 Detection.** ImageIO reports animation per frame in format dictionaries:
  `kCGImagePropertyGIFDictionary` (`UnclampedDelayTime`, `DelayTime`), `kCGImagePropertyPNGDictionary`
  (`kCGImagePropertyAPNGUnclampedDelayTime`, `kCGImagePropertyAPNGDelayTime`), `kCGImagePropertyHEICSDictionary`
  and `kCGImagePropertyWebPDictionary` (same keys). A file is animated when `CGImageSourceGetCount > 1` and frame 0
  has one of these delays. The unclamped value is preferred; ImageIO's clamped value already applies its own floor.
- **MED-008-D2 Storage format.** APNG written by `CGImageDestination` (`public.png`, frame count) with
  `kCGImagePropertyAPNGLoopCount` 0 and per-frame `kCGImagePropertyAPNGDelayTime`. Measured on the Mac (scratch
  program, 2026-11-14): 60 frames of 1024² encode in 0.33 s with a 272 MB footprint at `Finalize` (about 4.5 bytes
  per stored pixel); GIF output peaked at 698 MB and quantises colour. Hence APNG, and a 32 M stored-pixel cap on
  import (≈ 150 MB transient). The PNG sniffer (MED-014) skips ancillary chunks (`acTL`, `fcTL`, `fdAT`), so the
  scene archive content check accepts APNG; the extension stays `png`.
- **MED-008-D3 Delay clamp.** Browsers play delays under 20 ms (GIF "0" or "1") as 100 ms. Reduce flashing floor
  334 ms: at most 3 frame changes per second, i.e. at most 1.5 light/dark alternations per second, half the 3 Hz
  general flash threshold; the composite flash guard (FX-019, ACC-012) still limits the shown frame.
- **MED-008-D4 Looping.** Always loop; loop count written as 0 (spec Clarifications).
- **MED-008-D5 Clock.** MED-007's `KenBurnsPlayhead` with an unbounded limit is the frame-time counter (first frame
  0, then the injected durations, each ≤ 0.1 s). Index lookup: binary search over cumulative starts of
  `elapsed % total` (integer nanoseconds), so selection is exact and allocation-free.
- **MED-008-D6 Budget.** Device classes as PERF-005 (4 / 8 GiB): 32 / 64 / 128 MB for decoded animation frames
  (smaller than the prewarm cache, which holds whole stills). A frame decode transiently holds the ImageIO bitmap,
  the straight-alpha pixels, the premultiplied texels and the new texture (4 × w × h × 4), reserved while it runs.
  Decoded size: scale so that 6 frames (frame 0 and the frame on screen + 4 reserve) fit; each frame is accounted with
  one pixel of slack per side, since ImageIO may round a scaled size up. Textures are single-level `rgba8Unorm_srgb` (w × h × 4 bytes).
- **MED-008-D7 Decode scheduling.** One serial queue per animated picture; `request(i)` enqueues i and i + 1 unless
  resident or in flight; a decode result for a replaced picture is dropped (the picture object is released with
  its generation). The render thread takes the cache lock only with `withLockIfAvailable` (as the slot does).
- **MED-008-D8 Prewarm.** PERF-005 prewarms `decodeStored` (first picture, still). Adopting it stays instant; the
  layer then probes the file on its load queue and attaches the animation for the same generation.
- **MED-008-D10 Float delays.** ImageIO returns APNG/GIF delays as 32-bit floats (0.2 → 0.20000000298 s). Summed
  without rounding, frame starts drift 3 ns per frame and land just after an injected frame time, so a frame shows one
  frame late (found by the acceptance test). Delays are rounded to 0.1 ms before clamping.
- **MED-008-D9 Large fixture.** CGImageDestination retains every frame until `Finalize` (D2), so a 200 × 2048²
  fixture is written by hand: frame 0 full-canvas IDAT (zlib = `NSData.compressed(.zlib)` raw deflate with a zlib
  header and Adler-32), frames 1…199 a 64 × 64 `fdAT` patch at a moving offset, `CRC32` from MediaSniffing.
