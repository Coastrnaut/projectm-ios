# Research: SHD-001 Procedural Material Catalog

## SHD-001-D1: How shaders are "bundled at build time"

- **Decision**: The materials' Metal source is one Swift string constant
  (`ProceduralMaterialShaders.source`) compiled into the app binary; `prepare` turns it into a GPU
  library with `MTLDevice.makeLibrary(source:options:)` (safe math). That call is the module's only
  library creation, and its argument is that constant.
- **Rationale**: `xcrun metal` fails on the build Mac ("missing Metal Toolchain", checked
  2026-11-13), CI images are not guaranteed to have it, and ADR-0009 decision 3 already made
  every shader in the app (spectra, glow, compositor, flash guard, camera) a Swift constant. The
  source is part of the signed binary and cannot change after the build, which is what "no external
  code" protects: nothing is compiled from user text, documents, files or downloads.
- **Alternatives considered**: processed `.metal` resources in the package (needs the toolchain at
  build time; moving there later is a local change, as ADR-0009 notes); `.metallib` resources built
  elsewhere and committed (binary blobs that cannot be reviewed); `makeDefaultLibrary(bundle:)`
  (reads a bundle resource; same toolchain need).

## SHD-001-D2: Where the target lives

- **Decision**: Target `ProceduralMaterials` in `Packages/Compositor`, beside `CameraLayer`;
  Compositor gains a dependency on ParameterGraph.
- **Rationale**: Materials are layers; one library product keeps `-scheme Compositor` covering
  them; CI loops unchanged.
- **Alternatives considered**: a new package (more CI wiring); putting materials into
  VisualGenerators (it does not know the layer contract).

## SHD-001-D3: Parameter storage and uniforms

- **Decision**: A material's parameters are listed in order; parameter *i* is uniform slot *i*, a
  `float4` (scalars in `.x`, colors in `.rgba`). At most 8 slots. The fragment shader receives a
  144-byte struct (size, phase, audio level, 8 slots) with `setFragmentBytes`.
- **Rationale**: One generic uniform layout for every material; no per-material Swift structs to
  keep in step with the shader; no buffers to allocate.
- **Alternatives considered**: per-material structs (more layout code to keep in step); a
  `ParameterStore` read in `render` (it locks; render must not wait).

## SHD-001-D4: Clamping

- **Decision**: `MaterialParameterValues.set` applies MOD-001's store rules (contract C3.2):
  continuous clamped, integers clamped and snapped to the step, colors clamped per component,
  non-finite numbers, unknown IDs, wrong kinds and unknown enum cases refused with a typed error.
- **Rationale**: The same behavior a `ParameterStore` gives, without its lock, so a later row can
  feed values from a store (`update(from:)`) or set them directly.

## SHD-001-D5: Motion and music

- **Decision**: `MaterialMotion` keeps `phase` (Double, cycles) and `audioLevel` (0…1). Per frame:
  `dt` = the frame context's duration (already clamped to 0…0.1 s by `LayerFrameClock`, clamped
  again); target = mean of the finite band values clamped to 0…1 (0 with no bands); the level moves
  toward the target by at most 4·dt up and 1·dt down; `phase += dt · speed · (1 + reactivity ·
  level)`.
- **Rationale**: Deterministic from the frame sequence (no wall clock); speed changes never jump
  the picture (phase is integrated, not `time × speed`); music at most doubles the speed and never
  touches brightness (SHD-001-R10). Double precision keeps the phase smooth for days; it reaches
  the shader as a Float (resolution about 0.002 cycles after a day at full speed).
- **Alternatives considered**: driving brightness with music (a flash risk); using onset events
  (bursts; harder to bound); `presentationTime × speed` (jumps when speed changes).

## SHD-001-D6: Flash safety by construction

- **Decision**: Every time-dependent term in a shader advances by at most one cycle per unit of
  phase; speeds are bounded to |speed| ≤ 1 cycle per second; brightness ≤ 1; colors ≤ 1. With music
  the speed at most doubles. Starfield and Noise Flow move content spatially (no intensity change
  over time), so a flash area's mean changes slowly. Tests check the envelope at defaults (Reduce
  flashing thresholds, ≤ 2 transitions per window, composite guard gain 1) and at extremes (≤ 6).
- **Rationale**: A luminance oscillation at ≤ 2 Hz gives at most 4 transitions per second, within
  the Reduce flashing budget; the composite flash guard (ADR-0013 decision 6) still applies on top.

## SHD-001-D7: Golden signatures

- **Decision**: Per material at 64 × 64, frame 30 (0.5 s at 60 Hz), no music: mean and peak linear RGB
  and the pixels at (32, 32), (8, 8), (56, 16), (16, 56), stored as numbers in the test; tolerance 0.02
  per channel.
- **Rationale**: Small, reviewable, catches structural regressions (a broken formula moves the
  mean or the sampled points) while tolerating half-float rounding and GPU differences.

## SHD-001-D8: Determinism and seeds

- **Decision**: Hashes in the shader are integer-free float hashes with fixed constants per
  material (the seed is part of the material). Two layers drawing the same frame sequence give
  bit-identical pictures on the same GPU.
- **Rationale**: SHD-006 (noise editor) can later expose a seed parameter without changing the
  default output.
