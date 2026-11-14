# Research: PERF-003 Adaptive effect quality

## PERF-003-D1: Which effects adapt

- **Decision**: Only the FX-001 glow on the native spectrum host.
- **Rationale**: It is the only iterated multi-pass effect (prefilter, horizontal and vertical Gaussian of up to
  16 taps per side, composite): its cost scales with taps × reduced texels, so it has a cheap knob. FX-009
  trails, FX-020 chain passes, CMP-013 caching and VIS-004 persistence are single blends; dropping them changes
  the picture's content (trails vanish) for a small saving. The compositor's spectrum layers keep Full: they
  render inside a layered scene whose cost is dominated by other layers and are left to a later row.
- **Alternatives**: trails at half resolution (needs a second texture size and a resampling pass, i.e. new
  cost and visible softening); persistence off (abrupt content change).

## PERF-003-D2: The Reduced plan

- **Decision**: From Full's (D, R) with halo E = (R + 2)·D: if D' = 2D ≤ 8 and r = min(⌈R/2⌉, ⌊E/D'⌋ − 2) ≥ 1,
  use (D', r); otherwise (D, ⌈R/2⌉). Weights renormalized.
- **Rationale**: Halves the taps per side and, where possible, quarters the reduced texels, while E' ≤ E by
  construction. `BloomLuminanceModel.spreadRadius` and the FX-019 area model use Full's E, so they remain
  upper bounds at Reduced; the kernel still sums to one, so the luminance bound (Y + k·Y(P)) still holds.
- **Alternatives**: D' = 2D with r ≈ R/2 (same pixel radius) gives E' = (R + 4)·D > E — the halo would exceed
  the safety model's extent.

## PERF-003-D3: Minimal

- **Decision**: The glow pass is skipped (the effect is pass-through, the generator draws straight into the
  drawable).
- **Rationale**: The largest saving and the VIS-001 path, which already exists and is flash-limited.

## PERF-003-D4: Smoothing level changes

- **Decision**: A glow weight w ∈ [0, 1] multiplies the clamped glow intensity; a change fades w to 0 over
  0.4 s, switches the plan at w = 0, and fades back over 0.4 s. A change mid-fade reverses from the current w.
- **Rationale**: Changing the plan at zero glow is invisible; intensity-only changes do not rebuild the plan
  (MOD-002). One dip and rise per change is 0.8 s, far below 3 Hz, and every frame still passes the FX-019
  limiter with the luminance model of the glow actually drawn. Lowering w never brightens.
- **Alternatives**: cross-fading two renders (double cost while stressed); switching only at scene changes
  (could leave the device hot for minutes).

## PERF-003-D5: Inputs and hysteresis

- **Decision**: Thermal floor nominal/fair → Full, serious → Reduced, critical → Minimal; Low Power → at least
  Reduced; PERF-002 verdict over for 3 s → one step down; 10 s of good conditions → one step up. Thermal
  step-downs immediate.
- **Rationale**: Thermal states change slowly and already mean "reduce now"; a budget flag needs to persist
  (PERF-002 already filters with a p95 window and its own hysteresis). 10 s up vs 3 s down prevents flapping.
- **Note**: PERF-002's verdict exists only while the overlay is on (PERF-001 timing runs then). Running the timer
  always would add work to every frame; rejected.

## PERF-003-D6: Governor interaction (FR-049)

- **Decision**: `QualityGovernor.settings(thermal:lowPower:adaptiveEffects:)`. With `adaptiveEffects` (the host
  has the glow switched on), serious no longer caps to 30 fps; critical (30 fps, scale 0.75) and Low Power
  (30 fps) are unchanged. Without it, exactly today's table.
- **Rationale**: "Step down before the governor drops fps." Deferral is limited to when a glow exists to
  reduce, so a visual with nothing to adapt still gets today's thermal relief. FR-049 says MAY; no ADR.
- **Input**: the user's glow switch (`glow.enabled` with a working chain), not the modulated intensity, so the
  display link's range never flips per frame.

## PERF-003-D7: No user setting

- **Decision**: Automatic; no "Adaptive quality" toggle. The owner's Gate 3 ruling ("no quality tiers") was
  about measurement; here no tier is user-facing. A DEBUG launch argument injects the thermal state.
- **Rationale**: Fewer stored keys (FILE-005, FILE-011 untouched), no Settings edits, conservative.
