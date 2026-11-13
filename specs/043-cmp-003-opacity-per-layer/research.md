# Research: CMP-003 Opacity per Layer

Decisions taken by Claude under owner rule 4 (best judgement). The spec's Clarifications record the
product-level answers; this file records the technical ones.

## CMP-003-D1: Where opacity is applied

- **Decision**: In the existing composite pass: `cmp_over` returns its sanitized premultiplied
  colour multiplied by a `constant float &opacity` (`setFragmentBytes`, 4 bytes, per draw); the
  blend state stays (one, oneMinusSourceAlpha).
- **Rationale**: premultiplied "over" with opacity `o` is exactly `o·src + (1 − o·αs)·dst`, which is
  this multiply followed by the unchanged blend. In IEEE arithmetic `x × 1.0 = x` for every finite
  `x`, and the sanitizer has already removed non-finite values, so opacity 1 produces bit-identical
  output (CMP-003-R3). `setFragmentBytes` copies into Metal's own command memory: no `MTLBuffer` is
  created per frame (CMP-001-R9).
- **Alternatives**: blend constant colour (`.blendColor` factors) — would also work but changes the
  pipeline's blend factors for every layer and is harder to keep bit-identical; a separate pipeline
  for opacity < 1 — two code paths for one multiply.

## CMP-003-D2: Opacity 0

- **Decision**: a layer whose current opacity is exactly 0 is not drawn in the composite pass; it
  still renders into its picture and keeps its slots (spec Clarifications).
- **Rationale**: skipping the draw makes the output equal the stack without the layer bit for bit
  (CMP-003-R4), and saves one full-screen draw.

## CMP-003-D3: Interpolation helper

- **Decision**: a local pure helper in `LayerOpacity.swift`: position `t = min(elapsed / duration, 1)`,
  curve (linear `t`; ease-in-out smoothstep `t²(3 − 2t)`), value `t ≥ 1 ? target : start + s·(target − start)`
  clamped to the segment's ends.
- **Rationale**: the `Compositor` target depends only on AnalysisFeatures and FlashSafety; adding
  ParameterGraph for a two-line lerp would widen the core module's dependencies and touch
  `Package.swift`, which SHD-002 also edits. Returning the target exactly at `t ≥ 1` and clamping to
  the ends gives MOD-003's guarantees (exact ends, never outside, monotonic: IEEE multiply and add
  are monotonic in their operands).
- **Alternatives**: `ParameterGraph.LinearMapping` (MOD-003) — rejected for the dependency reason.

## CMP-003-D4: Time base

- **Decision**: `LayerOpacityAnimator.advance(by:)` takes the frame clock's `frameDuration`
  (clamped to 0…0.1 s; frame 0 has 0). Non-finite or negative durations count as 0.
- **Rationale**: deterministic from injected frame times; a stall never completes a fade in one
  frame; the same rule all layer animations follow (CMP-001-R3).

## CMP-003-D5: Retargeting and when a fade starts

- **Decision**: `setOpacity` starts the new segment from the animator's current value (the value
  shown at the last frame) with elapsed 0. The compositor calls `advance` once per frame before
  reading the value, so the first frame after an apply with a fade shows `start + curve(dt/d)` —
  one frame's progress — and a zero duration shows the target at that frame.
- **Rationale**: continuity (no jump) and exact end; a zero-duration change is immediate.

## CMP-003-D6: API shape

- **Decision**: `Compositor.apply(_ stack:, opacityTransition: LayerOpacityTransition = .immediate, makeLayer:)`.
  Existing `apply(stack) { … }` calls compile unchanged. `LayerOpacityTransition(duration:curve:)`
  validates in a throwing initializer (`LayerOpacityError.nonFiniteDuration`, `.negativeDuration`);
  `LayerOpacityAnimator.setOpacity(_:duration:curve:)` throws `.nonFiniteTarget` as well.
  `CompositorError` is unchanged: an invalid transition cannot reach `apply`.
- **Rationale**: one source of truth (the stack); typed errors; minimal change to shared files.

## CMP-003-D7: Refusals that remain

- **Decision**: a new `LayerCompositeSettings.isSupportedByCompositor` (normal blend, identity
  transform) replaces the compositor's use of `isSupportedByCMP001`, which is kept with its
  meaning (identity values) for compatibility.

## CMP-003-D8: Flash safety

- **Decision**: no change to the guard. Opacity changes the composite the guard measures, so a 30 Hz
  0↔1 opacity strobe is limited like any picture strobe; opacity never calls `resetFlashHistory`.
  Test: white over black, opacity alternating every 2 frames at 60 fps (30 Hz), 2 s, Reduce
  flashing on, analysed with FlashSafety's `FlashAnalysis` (≤ 4 transitions per 1 s window, rise per
  frame ≤ 0.25/60 + 1e-3), as CMP-001-T12.

## CMP-003-D9: Device measurement

- **Decision**: no new device task. The opacity multiply adds one constant to a draw that exists;
  CMP-002-T15 (per-layer frame cost of a 4-layer stack on D1-D3) measures the composite pass that
  carries it (spec CMP-003-S6).
