# Research: VIS-001 Circular Spectrum

Decisions are numbered `VIS-001-D1…` and cited from the plan, the data model and the code.

## VIS-001-D1: Where the native visual lives

- **Decision**: a new package `Packages/VisualGenerators` with a dependency-free `VisualGenerators`
  target (contract, geometry, palette, limiter, triple buffer, Metal generator) and a
  `VisualBandFeed` target (AnalysisFeatures → bands). One library product, so CI's
  `-scheme VisualGenerators` covers both targets and the tests.
- **Rationale**: the roadmap's proposed layout names it; `Rendering`/`ANGLERendering` are projectM
  adapters and iOS-only (no Linux tests); `AnalysisFeatures` must not draw. Keeping the generator
  target free of analysis lets CMP-001 adopt it with any input.
- **Alternatives**: extend `Rendering` (couples to projectM and GLES, no Linux); put everything in the
  app (untestable on Linux, not reusable by VIS-002/003/006/020).

## VIS-001-D2: Geometry on the CPU, a thin GPU pass

- **Decision**: the CPU lays out one `BarGeometry` per bar (centre angle, half-width, inner/outer
  radius in pixels, linear color) and tessellates each bar as an annular sector of 4 arc segments
  (24 vertices, two triangles per segment) in normalized device coordinates. The GPU pass passes
  positions through and fills flat premultiplied colors.
- **Rationale**: the acceptance ("lights the correct angular segment") is then provable on every
  host, including Linux and GPU-less CI, by inspecting the same numbers the GPU draws. Radial sides
  are exact lines; only the arcs are chords (error at the outer radius of the widest bar, 16 bars
  with gap 0.2, 18°/4 = 4.5° per segment: 1 − cos(2.25°) ≈ 0.08 % of the radius).
- **Alternatives**: a full-screen fragment shader evaluating polar coordinates per pixel (no vertex
  data to test, all logic on the GPU); instanced quads with a vertex shader that bends them (geometry
  hidden in shader code).

## VIS-001-D3: Shader build

- **Decision**: the Metal shader source is a `static let` string in `CircularSpectrumGenerator.swift`,
  compiled once with `MTLDevice.makeLibrary(source:options:)` when the generator is created.
- **Rationale**: measured on the build Mac (2026-11-13): `swift build` of a package with a `.metal`
  resource fails with "cannot execute tool 'metal' due to missing Metal Toolchain"; Xcode 27.2 ships
  the Metal Toolchain as a separate download (`xcodebuild -downloadComponent MetalToolchain`) that is
  not installed here, and GitHub's images are not guaranteed to carry it. Runtime compilation goes
  through the system's Metal framework (verified on the host: a library compiled from a source
  string on "Apple M5 Max"), needs no toolchain, and keeps the package free of resources, so Linux
  needs nothing special. The source is a compile-time constant; nothing is read from a file or the
  network (VIS-001-R17). The one-time compile cost is paid when the visual is first chosen.
- **Alternatives**: `.metal` resource with `.process` (fails without the toolchain); a prebuilt
  `.metallib` committed to git (a binary artifact per platform/SDK, opaque to review).

## VIS-001-D4: Pixel format, alpha, color space

- **Decision**: `bgra8Unorm_srgb` default (also `rgba16Float`); colors linear and premultiplied;
  palette defined in sRGB hex and decoded to linear once per configuration; clear color opaque black
  by default, configurable (premultiplied) so a compositor can request transparency.
- **Rationale**: blending and the Reduce-flashing luminance math are correct in linear light; the
  `_srgb` format makes the hardware encode on write and is a supported `CAMetalLayer` format. The
  ANGLE layer stays `bgra8Unorm`; the two are never composited in this row.

## VIS-001-D5: Band input path

- **Decision**: turn on the existing analysis tap (ANL-001-R9) through a new
  `analysisTapCapacityFrames` parameter of `AudioAnalyzer` and `CaptureManager` (default 0); the app
  passes 22,050 frames (0.5 s). `LiveBandAnalyzer` runs a `DispatchSourceTimer` every 10 ms on its
  own serial queue (`org.projectmios.visual-analysis`, QoS user-interactive) only while the native
  visual is running; each tick pulls the tap through `SpectrumBandFeed` (FFT 2,048, hop 512, mid,
  44.1 kHz → BandReducer → `BandMath.normalize(.decibels(−80))`) and publishes the newest band vector
  into `BandFrameBuffer`. The frame loop takes the newest frame without waiting.
- **Rationale**: smallest correct path before ANL-016; nothing new on the audio thread; the tap's
  drop-oldest policy bounds memory while nobody reads it; projectM's ring reads are unaffected by
  construction (ANL-001-R9 tests). Hop 512 gives about 86 spectra per second, more than the frame
  rate, so the newest frame is never older than about 12 ms plus the window.
- **Resolution note (measured 2026-11-13, VIS-001-T15)**: a 2,048-point spectrum has 21.5 Hz bins.
  Low bands at 64 and 128 bars are narrower than that (100 Hz at 128 bars: 0.25 bins wide), so a
  100 Hz sine lights a cluster of neighbouring sub-bin bands whose overlap-weighted values differ by
  less than 1 %; the loudest can be the neighbour of the band containing 100 Hz. The first band-feed
  test expected exact equality everywhere and failed for 100 Hz at 64/128 and 440 Hz at 128. The
  acceptance was restated (VIS-001-S4) rather than changing the analysis: exact where the band is at
  least two bins wide (11 of 16 cases), within one bin otherwise. A larger FFT for the low bands is
  ANL work, not this row's.
- **Alternatives**: read projectM's ring (would steal its audio); compute on the main thread in the
  frame callback (main-thread work, violates the brief); always-on tap in AudioCore (changes every
  user of the analyzer).

## VIS-001-D6: Lock-free hand-off

- **Decision**: a triple buffer: three fixed slots of 128 Floats plus a count and time; the writer
  fills its private slot and atomically exchanges it with the shared middle index (with a "fresh"
  bit); the reader exchanges its slot with the middle only when the bit is set. `Atomic<Int>` from
  Synchronization (also on Linux).
- **Rationale**: wait-free for both sides; no lock on the render path; the reader always gets a
  complete, newest frame.

## VIS-001-D7: Reduce flashing

- **Decision**: per-bar slew 4.0/s and a mean-luminance rise limit of 0.25/s (frame time clamped to
  0…0.1 s), applied as a uniform gain on colors; mean relative luminance = Σ area_k · Y_k / (W·H) with
  area_k = halfWidth_k · (r_out² − r_in²) (exact sector area) and Y_k the palette color's linear
  relative luminance (0.2126 R + 0.7152 G + 0.0722 B), background included.
- **Rationale**: mirrors the projectM limiter's semantics (a rate on mean luminance) with an exact,
  CPU-testable quantity; colors do not depend on band values (VIS-001-R6), so luminance changes only
  through area and the gain. 0.25/s is stricter than projectM's 0.3/s.

## VIS-001-D8: Frame loop and lifecycle

- **Decision**: a `CADisplayLink` on the main run loop, frame-rate range from `QualityGovernor`
  (as ANGLE), drawing into the `CAMetalLayer`'s next drawable; `drawableSize` follows the view's
  bounds × scale on layout (rotation). The host is a `PresentationBoundResource`: suspend stops the
  link and the analyzer and drops the drawable reference; resume restarts them unless paused.
  Vertex data uses three preallocated `MTLBuffer`s; a buffer is reused only when the command buffer
  that last read it reports `completed`, otherwise the frame is skipped (no wait, no closure).
- **Rationale**: same lifecycle as ANGLERenderer (PERF-011), no blocking on the main thread.
