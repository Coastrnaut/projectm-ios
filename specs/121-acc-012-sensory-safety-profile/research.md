# Research: ACC-012 Sensory Safety Profile

The audit is in spec.md ("Baseline"). Decisions:

## R1 Where the model lives

- **Decision**: `SensorySafetyProfile` and `SafetyClamp` in the FlashSafety package.
- **Rationale**: FlashSafety is pure Swift, tested on Linux in CI (`.github/workflows/ios-ci.yml` lists it in
  every package loop), holds FX-019's `FlashEnvelopeConfiguration`, and every renderer package already
  depends on it (VisualGenerators, Rendering/ANGLERendering, Compositor). One definition of a flash and of
  its limits stays in one place.
- **Alternatives**: a new package (more CI wiring, one more dependency edge); app-only types (not
  Linux-testable, renderers could not name them).

## R2 Mapping the flash limit (no second limiter)

- **Decision**: flashes per second f ∈ {1,2,3} → `transitionBudget = 2f`; rise limit r → `riseRatePerSecond`
  (nil = none). Thresholds, window, gate margin and frame-time clamp keep FX-019's values, so the GLSL port
  (`CFlashLimiter`) and the compositor's Metal guard need no change: they already read every field.
- **Presets**: Standard (3, none) = `.alwaysOn`; Reduced (2, 0.25) = `.reduceFlashing`; Strict (1, 0.10).
- **Alternatives**: lowering the luminance threshold (changes the WCAG definition shared by GPU tests).

## R3 The clamp point

- **Decision**: one value, `SafetyClamp`, computed on the main actor whenever the profile or Reduce
  flashing changes, handed to each frame resolver: `NativeSpectrumHost.resolveEffectiveGlow()` (after
  `AudioFeatureModulator.value`, before `BloomEffect.parameters` and the generator's luminance model), the
  host's `VisualFrameContext` (`flashLimits`), `ANGLERenderer.flashLimits`, `Compositor.flashLimits` (final
  composite guard) and `GeneratorGraphLayer.intensityLimit` (speed before `GraphMotion.advance`).
- **Standard bit identity**: `SafetyClamp.flashLimitsOverride` is nil whenever the effective configuration
  equals `forReduceFlashing(reducesFlashing)`, and each cap returns its input unchanged when the intensity
  limit is 1, so no arithmetic touches a Standard value.
- **Alternatives**: clamping in the settings UI (bindings and scenes bypass it); clamping inside
  `AudioFeatureModulator` (unbound manual values would not be capped, and the registry is shared with
  scene validation).

## R4 Precedence

- **Decision**: per limit the stricter value wins (fewer flashes, lower rise rate, lower intensity). The
  effective Reduce flashing (stored choice, else system Reduce Motion) floors the flash limit at Reduced's;
  Reduce Motion alone does not touch the intensity limit (ACC-001-R5). A profile with a flash limit
  stricter than Standard sets the effective Reduce flashing on (bar slew, ACC-002, restore fade) without
  writing `settings.reduceFlashing`.

## R5 Binding depth

- **Decision**: effective = manual + limit × (modulated − manual), then the target's own cap
  (glow intensity ≤ limit × 1.0). Scaling the excursion keeps the binding's motion proportionally smaller;
  the final cap guarantees no binding passes the limit.

## R6 Haptics, projectM, speed

- Haptics: none in the app (grep for `UIFeedbackGenerator`, `UIImpactFeedbackGenerator`, `CHHapticEngine`,
  `sensoryFeedback`: 0 hits). Nothing to clamp; recorded.
- projectM: preset motion (zoom, rotation, warp) is engine-internal per-preset equations, not parameters the
  app resolves; what applies is the flash envelope at the profile's limits and ACC-002's "May flash" policy
  (on whenever the effective Reduce flashing is on).
- Speed: SHD-002 `GeneratorGraphLayer` gets the cap (|speed| ≤ limit × `speedCap`); SHD-001 materials and
  oscillator rates are not composed by the app (no oscillators exist); documented for when they are.
