# Research: VIS-002 Linear Spectrum

All open questions were settled in the spec's Clarifications; these are the design decisions.

## VIS-002-D1 Share VIS-001's plumbing instead of copying it

- **Decision**: Factor the circular generator's Metal pass (pipeline from the runtime-compiled
  shader, three shared vertex buffers released by command-buffer status, clear-and-draw) into
  `FlatShapePass`, and the 17-area computation into `SpectrumFlashAreas` generic over a small
  internal protocol (`FlashRegionLayout`: width, height, region count, background, per-region area,
  color and convex pixel quads). Both generators then differ only in their layouts.
- **Rationale**: one pipeline and one flash model to keep correct (FX-019's guarantees hold for
  both by construction); VIS-003 and VIS-020 can reuse the same pieces.
- **Alternatives**: copy `CircularSpectrumGenerator` (two pipelines and two area models to keep in
  step); a GPU-side area measurement (needs a readback per frame, violates the latency budget).
- **Safety net**: the refactor commit changes no test; VIS-001, FX-001 and FX-019 suites must pass
  unchanged before and after it.

## VIS-002-D2 Geometry in length/cross coordinates

- **Decision**: compute every bar in (cross, length) pixel coordinates, then map: vertical
  `x = cross, y = H − length`; horizontal `x = length, y = cross` (y down). One code path, two
  mappings; tests check both.
- **Rationale**: orientation is a pure axis mapping, so count, spacing and bounds rules are shared
  and proved once.

## VIS-002-D3 Peak caps on the frame clock

- **Decision**: `PeakCapTracker` keeps per-bar peak and remaining hold, advanced by the frame
  context's frame duration clamped to 0…0.1 s; hold time used up mid-frame flows into the fall
  (exact piecewise motion). Reset on bar-count or orientation change and on the host's loop
  restart.
- **Rationale**: deterministic and testable with an injected clock (no wall time, CI lesson);
  bounded per-frame motion.
- **Alternatives**: gravity/acceleration falls (more parameters, harder to test); time stamps from
  `CACurrentMediaTime` (wall clock).

## VIS-002-D4 Caps and flash safety

- **Decision**: caps are flat rectangles in the bar's color, so a frame is a set of flat regions
  (bars and caps, never overlapping because λ ≤ 1 − t and p ≥ v) and the envelope's per-tile levels
  are exact rectangle-tile intersections; the glow's light uses the shared halo spread estimate
  (FX-019-D6). The generator calls the same `FlashSafetyLimiter` path as the circular spectrum.
- **Rationale**: FX-019-R9 requires native visuals to feed the envelope after every effect; using
  the shared code path guarantees it.
- **Measured during implementation (VIS-002-T09)**: with fractional cross-axis edges the GPU
  covered whole pixels (a 1.6 px bar rasterized 2 px wide), so the whole-frame level measured 25 %
  above the model (0.863 vs 0.693) and the envelope under-limited. Cross-axis edges are therefore
  rounded to whole pixels; after that the measured whole frame matches the model within 0.004.
  Lengths stay continuous (at most half a pixel per bar end).

## VIS-002-D5 App host

- **Decision**: rename `CircularSpectrumHost` to `NativeSpectrumHost` holding
  `any SpectrumTextureGenerator`; a style change between kinds builds the other generator on the
  main thread outside the frame callback and swaps it; the envelope history is reset with the new
  generator (a new visual, FX-019-R11). A failure to build it marks the native visual unavailable
  (fallback to projectM, VIS-001-R16).
- **Rationale**: one frame loop, one analyzer, one glow chain; the lifecycle code stays in one
  place.
- **Alternatives**: a second host class (duplicates ~250 lines of lifecycle code); two generators
  alive at once (doubles GPU buffers for nothing).

## VIS-002-D6 Settings

- **Decision**: segmented pickers Orientation (`orientationPicker`) and Spacing (`spacingPicker`),
  shown only for Linear Spectrum; Bars and Glow shown for both native visuals. Keys and fallbacks
  per VIS-002-R11.
- **Rationale**: matches the existing Settings pattern; no new screen.
