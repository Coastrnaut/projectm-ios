# Research: VIS-003 Waveform Oscilloscope

## VIS-003-D1: How samples reach the frame loop

- **Decision**: `WaveformTap`, a pass-through `NormalizedPCMReader` (and `AnalysisSessionReporting`)
  around the analysis tap. The analyzer's pipeline reads through it; each read is forwarded
  unchanged, then its frames are mixed to mono ((L + R)/2, the pipeline's `.mid` mode) into a fixed
  4,096-sample rolling history, which is published through `WaveformFrameBuffer` (a triple buffer
  like `BandFrameBuffer`, one atomic exchange per side). The frame loop copies the newest history
  (16 KB) into a preallocated scratch. The session generation is forwarded (0 when the wrapped reader
  does not report one, which the pipeline reads as "never changes", its existing behavior).
- **Rationale**: the tap has exactly one consumer; the pipeline already reads it on its own worker
  every 10 ms; wrapping costs one mono mix and one 16 KB copy per read (about 100 per second) and
  changes no shared type. The bands are bit-identical because the forwarded bytes are untouched.
- **Alternatives**: a second tap (violates the single-consumer contract); samples on the ANL-016 bus
  (every subscriber copies them; shared-type change); reading the tap in the frame loop (would starve
  the analyzer).

## VIS-003-D2: Trigger stabilization

- **Decision**: per frame, over the span the trigger may use (history positions 0 … H − W, plus the
  window): level = mean, range = max − min. Silence if range < 0.002. Hysteresis h = 0.05 × range:
  scan the candidate span, arm when x < level − h, and on the first sample ≥ level after arming
  record a crossing at the interpolated fraction, disarm; keep ≤ 32 crossings (the newest ones win
  when more occur; the scan runs from the oldest sample and keeps the newest 32 in a ring). With ≥ 3
  crossings, intervals' standard deviation / mean > 0.35 → aperiodic. Choose: if a 64-point reference
  of the previous window exists, score each crossing by SSD between the reference and the 64-point
  resample of its window and take the newest within 1.05 × best + 1e-4; else the newest. Store the
  chosen window's 64 points as the next reference. Free-run: start = H − W, reference cleared.
- **Rationale**: a rising crossing of the mean with hysteresis is the classic scope trigger and
  handles DC offsets and moderate noise; the match criterion makes the choice among same-phase
  crossings of complex periodic waves consistent frame to frame (the "previous phase" requirement)
  in O(candidates × 64). For pure periodic signals every crossing has the same phase, so the newest
  is chosen (least latency) and the phase is exact up to interpolation error.
- **Alternatives**: full autocorrelation period estimation (O(n²), too slow for every frame);
  zero-level trigger (fails with DC); "newest crossing" only (jumps between harmonics' crossings).

## VIS-003-D3: Drawing the line

- **Decision**: P = min(W, 1,024) points; segment quads extended by T/2 at both ends (square caps),
  flat color per segment from the palette by index; drawn by the shared `FlatShapePass`; each
  segment is one `FlashRegionLayout` region, so the envelope's 17-area levels come from the shared
  `SpectrumFlashAreas` (overlapping caps double-count a few pixels: conservative).
- **Rationale**: reuses the pass, the area model, the glow and the limiter unchanged; Metal has no
  wide lines.
- **Alternatives**: a new shader with a geometry expansion in the vertex stage (new shader code, and
  the CPU area model would still need the quads).

## VIS-003-D4: Golden image without a scene

- **Decision**: a generator-level golden in `Packages/RenderGoldens/GeneratorGoldens/<class>/`,
  using QA-002's `GoldenImage`, `GoldenComparison`, `GoldenDecision`, `GoldenStore`,
  `GoldenRecordPolicy`, `GoldenArtifacts` and `GoldenIntegrity.check(goldensRoot:runs:)` with a
  one-entry catalog (`GoldenSceneRun(name: "waveform-oscilloscope-sine", …)`, captured frame 1 after
  a warm-up frame). The sine (440 Hz, amplitude 0.8, phase 0 at the history's start) is computed in
  the test; rendering is `OscilloscopeGenerator` into a `bgra8Unorm_srgb` texture read back and
  swizzled to RGBA.
- **Rationale**: the scene path needs a new SCN-001 kind and samples in the compositor's audio
  context (out of scope, spec Clarifications); the generator golden still uses the exact QA-002
  rule, policy and integrity machinery.

## VIS-003-D5: Allocation proof

- **Decision**: as VIS-001/VIS-002: all storage is allocated in `init` as fixed-capacity pointers;
  tests run 1,000 frames and check the exposed capacities and base addresses never change, and the
  frame path takes only `UnsafeBufferPointer`s. The device check under Instruments (allocations and
  frame time on D1) is `{device}`.
- **Rationale**: XCTest has no portable allocation counter that works on Linux; fixed storage with
  stable addresses plus code review of the frame path is the established evidence here.
