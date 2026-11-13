# Research: QA-002 Golden Render Scenes

## QA-002-D1 Where the golden system lives

- **Decision**: a new package `Packages/RenderGoldens` (plain target `GoldenImages`, Metal target
  `SceneRenderHarness`, test target `RenderGoldensTests`).
- **Rationale**: it needs SceneFormat plus every layer target; Compositor cannot depend on SceneFormat
  (the reverse dependency exists). A separate package keeps other suites unchanged and gives QA-003
  and QA-006 a home.
- **Alternatives**: a test target in SceneFormat (mixes codec tests with GPU goldens and grows that
  package's CI time); per-feature golden files (what exists; not scene-level, not reviewable).

## QA-002-D2 Locating fixtures

- **Decision**: `Scenes/` and `Goldens/` at the package root, found from the test sources' `#filePath`.
- **Rationale**: record mode must write into the source tree; the simulator's test process can read
  and write host paths; no resource bundle copies to keep in sync.
- **Alternatives**: SwiftPM resources (read-only copies; record would need a second path anyway).
  Physical devices cannot reach the host path: device goldens are a later stage (spec Assumptions).

## QA-002-D3 Capturing the frame as shown

- **Decision**: render into an `rgba16Float` output with `reduceFlashing: true`; for captured frames,
  `Compositor.requestFrameCapture` before `composite`; convert with
  `FrameColorConversion.rgba8(_, policy: .preserveCoverage)` (straight-alpha 8-bit sRGB) and encode PNG
  with `FrameImageEncoder`.
- **Rationale**: exactly REC-001's "as shown" path (composite × flash guard gain); no new shader.
- **Alternatives**: reading an 8-bit sRGB output texture (a second, different conversion).

## QA-002-D4 Determinism of inputs

- **Decision**: frames at 1 s + n/60 s (n = 0…7), `contentScale` 2; audio bands per frame from a
  SplitMix64 stream seeded per scene (32 bands, values in a fixed range), or a fixed alternating
  0/1 pattern for the strobe scene; no analysis events. Photos are generated RGBA gradients with
  seeded stripes, encoded to PNG in a temporary file and loaded through the photo layer. Frame 0 is a
  warm-up: after it the harness waits for photo loads (`waitUntilLoaded`) and text rasterization
  (`waitUntilRendered`), then resets the composite flash history (found on the simulator: frame 0 sometimes
  already showed the photo, and the guard's history carried that into frame 7).
- **Rationale**: each layer's tests already show bit-identical output for identical inputs; the only
  timing-dependent parts are the two asynchronous loaders, settled before any capture.

## QA-002-D5 Hashing on Linux

- **Decision**: a small SHA-256 in Swift (FIPS 180-4), tested with the standard vectors ("", "abc",
  the 448-bit message, one million "a" is too slow for budget: a 1 KB pattern cross-checked with
  CryptoKit on Apple platforms).
- **Rationale**: CryptoKit is Apple-only; adding swift-crypto is a new dependency (Constitution IX).

## QA-002-D6 Platform classes and CI

- **Decision**: `macos` and `ios-simulator`. Devices have none (pending, not passed). GPU name and
  OS version are informational in the manifest. Text scenes compare only on the recorded OS
  major.minor.
- **Rationale**: spec Clarifications. Risk recorded: CI's GPU (GitHub's virtualized macOS runner)
  and OS 26 differ from the Mac Studio's; the SHD-001 signatures already pass there within 0.02, but
  per-pixel goldens were not proven on CI before the first push. If CI differs beyond the tolerance,
  the diff artifacts in the job's xcresult show it, and QA-003's configurable tolerance or a CI class
  is the follow-up. A local cross-check on the iOS 26.5 simulator runtime against the iOS 27.2
  simulator goldens gives early evidence across OS versions.

## QA-002-D7 Tolerance

- **Decision**: `GoldenTolerance.qa002`: channel threshold 2 (of 255), allowed fraction 0.001 of
  pixels rounded down (12 of 12,288 at 128 × 96; 49 of 49,152 at 256 × 192); size mismatch fails.
- **Rationale**: absorbs one-step rounding differences between float paths, fails any visible change.

## QA-002-D8 Diff image

- **Decision**: same size as the frames; unchanged pixels are the expected pixel's luminance at 30 %
  (grey, opaque); pixels within the tolerance are yellow; pixels above it are red with brightness
  scaled from 128 to 255 by the difference; a size mismatch gives a diff of the larger size with the
  non-overlapping area magenta. Also written: `expected.png`, `actual.png`, `diff.png`, `summary.txt`.

## QA-002-D9 Record switch and CI guard

- **Decision**: `GOLDEN_RECORD=1` records; `CI` or `GITHUB_ACTIONS` present refuses recording (test
  failure, nothing written). Simulator: `TEST_RUNNER_GOLDEN_RECORD=1`. Unchanged pixels: file kept.
- **Rationale**: GitHub Actions sets both variables on the host; on the simulator CI never passes the
  `TEST_RUNNER_` variable, and the integrity test (Linux and host) fails on any missing golden, so an
  incomplete set cannot pass CI either way.

## QA-002-D10 Scenes (all authored here, MIT like the repository)

| Name | Layers (bottom → top) | Covers |
|---|---|---|
| `photo-gradient` | photo (seeded gradient, fill) | MED-001 decode, upload, scale |
| `material-plasma` | material.plasma (scale 3, saturation 0.8) | SHD-001, parameters, audio bands |
| `graph-hue-rings` | generator graph "Hue Rings" (SHD-002 example) | SHD-002 interpreter, SHD-011 import |
| `spectrum-circular` | circular spectrum, seeded bands | VIS-001, FX-001 glow defaults |
| `stack-composite` | photo; material.gradient at 0.6 rotated and scaled; linear spectrum translated | CMP-002/003/005 |
| `strobe-guarded` | linear spectrum with bands alternating 0 and 1 every frame | FX-019 composite guard (frames 6 and 7) |
| `text-caption` | material.gradient; text "QA-002 golden" | MED-009 (OS-sensitive) |
