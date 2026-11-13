# Research: MOD-002 Audio Feature Binding

Each decision: what was chosen, why, and what was rejected. Decided by Claude under owner rule 4
(2026-11-13); no ADR is needed because nothing here overrides a default of ADR-0012.

## MOD-002-D1: Where the model lives

- **Decision**: `Packages/ParameterGraph`, beside the registry and store; three new files.
- **Rationale**: a binding is validated against the registry's descriptors and policies; the module
  is dependency-free and Linux-tested (MOD-002-R10). MOD-011 (mix ordering), MOD-013
  (serialization) and MOD-014 (cycles) extend the same types.
- **Rejected**: a new `ModulationGraph` package (one more CI loop entry for ~350 lines; no
  boundary gained); putting it in `AnalysisFeatures` (the analysis side must not know parameters).

## MOD-002-D2: Feature input without a dependency on analysis types

- **Decision**: `AudioFeatureFrame` holds an `UnsafeBufferPointer<Float>` of band levels (borrowed
  for the call), an optional onset value and an optional beat confidence. Callers adapt their own
  buffers: the native host passes its band scratch; a later consumer of `AnalysisSubscription`
  passes the copied bands plus `AnalysisFrame.onsetFlux` and `beatConfidence`.
- **Rationale**: no copy, no allocation, no dependency on `AnalysisFeatures` (Constitution VI).
- **Rejected**: depending on `AnalysisFrame` (couples ParameterGraph to analysis); an array per
  frame (allocation).

## MOD-002-D3: Source identity

- **Decision**: `AudioFeatureSource` cases `band(Int)`, `bandMean`, `onset`, `beatConfidence` with
  stable IDs `audio.band.<index>` (decimal, no leading zeros), `audio.bandMean`, `audio.onset`,
  `audio.beatConfidence`; `init?(id:)` parses exactly these. Band index 0…127 (the largest band
  count, ANL-002 / `SpectrumBarCount.maximum`).
- **Rationale**: readable, round-trips for MOD-013, cannot collide with parameter IDs (`audio` is
  not a parameter domain).
- **Rejected**: band position as a fraction of the spectrum (more design than the acceptance
  needs; can be added as a new case later).

## MOD-002-D4: Mapping and mix arithmetic

- **Decision**: signal `x = clamp((f − inMin) / (inMax − inMin), 0, 1)`, smoothed to `s`; mapped
  `m = (1 − s)·out0 + s·out1` (exact at both ends, inverted when `out0 > out1`); effective =
  `m` (replace), `manual + m` (add), `manual · m` (multiply), clamped to the target range; integers
  round half away from zero, then snap like the store (`ParameterStore.normalized`). Output ranges:
  replace within `[min, max]`; add within `±(max − min)`; multiply within `0…1`.
- **Rationale**: exact endpoints satisfy MOD-003's later test; multiply ≤ 1 means audio can only
  lower a manual value (conservative for light); the final clamp keeps every result legal.
- **Rejected**: `out0 + s·(out1 − out0)` (not exact at `s = 1` in floating point); unbounded
  multiply factors.

## MOD-002-D5: Envelope and clock

- **Decision**: one-pole per binding: `s += (x − s)·(1 − exp(−Δt/τ))` with `τ` = attack when
  `x > s`, release otherwise; `τ = 0` sets `s = x`. `Δt` comes from consecutive
  `timeNanoseconds` values passed to `advance` (the frame's display time in the app): ≤ 0 → 0, capped
  at 0.25 s; the first `advance` after binding has `Δt = 0`. Signals start at 0. Time constants
  0…60 s.
- **Rationale**: deterministic (MOD-002-R9), allocation-free, the standard envelope follower; after
  one time constant a step reaches 1 − e⁻¹ ≈ 63.2 %, testable within 1 % (MOD-002-S3). The cap stops
  a resumed loop from jumping on stale state.
- **Rejected**: per-sample smoothing (the modulator runs per frame); linear ramps (rate depends on
  the step size).

## MOD-002-D6: Applying a modulated glow without per-frame allocation

- **Decision**: (a) `BloomEffect.parameters` recomputes the plan only when a field other than
  `intensity` changed; an intensity-only change updates the uniforms (the plan never reads the
  intensity). (b) The host sets the generator's `downstreamLuminance` once to a small final class
  `ModulatedGlowLuminance` (a `FrameLuminanceTransfer` holding a mutable `BloomLuminanceModel`,
  mutated only on the main thread) and updates its model each frame.
- **Rationale**: a new `BloomPlan` allocates its weight array, and assigning a 32-byte struct to an
  existential allocates a box; a class reference does neither. The Reduce-flashing limiter (FX-019)
  then sees the effective intensity every frame (MOD-002-R11).
- **Rejected**: a model at the binding's maximum intensity (the limiter would miss the variation
  modulation itself creates); allocating per frame (Constitution VII spirit, the host's
  "allocates nothing per frame" contract).

## MOD-002-D7: Isolation

- **Decision**: `AudioFeatureModulator` is a non-`Sendable` final class used by one owner (the app's
  main-thread frame loop); slots live in an array reserved for 32 at init; lookups scan slots.
- **Rationale**: no lock per frame; Swift 6 checking keeps it on its owner. MIDI/OSC rows will hand
  changes to the owner.
- **Rejected**: a `Mutex`-guarded modulator (a lock per frame for no current need); an actor (hops
  per frame).

## MOD-002-D8: App scope and the Debug test path

- **Decision**: no editor and no persistence. The host owns the modulator; the Debug launch argument
  `-uitestBindGlowToBass` binds `audio.band.0` → `effect.bloom.intensity` (replace 0…1, no
  envelope). A DEBUG panel shows `glowModulation` ("bound, manual 0.50, effective 0.73", refreshed 4
  times a second) and a `glowModulationUnbind` button. The UI test sets the visual and glow through
  launch-argument defaults (`-settings.visual circularSpectrum -settings.circularSpectrum.glow YES`)
  instead of tapping through Settings. `AppSettings` is not routed through `ParameterStore`: the
  manual glow intensity the frame loop already holds is the base value.
- **Rationale**: the smallest path that a simulator can verify (MOD-002-S4) while Release builds
  contain none of it; the UI test stays short.
- **Rejected**: a user-facing binding switch (MOD-012's matrix UI); routing settings through the
  store now (touches Settings and persistence for no user benefit in this row).
