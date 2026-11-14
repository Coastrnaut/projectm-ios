# ADR-0049: One Sensory Safety Clamp, Applied After Modulation and Before Render; the Stricter Limit Wins

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: ACC-012 (`specs/121-acc-012-sensory-safety-profile`)
- **Constitution**: VI (modular boundaries: the model lives in FlashSafety, renderers take a plain
  envelope configuration), VII (no allocation, lock or I/O per frame), VIII (no engine change), X
  (evidence: renderer-input table test, GPU bit identity); privacy (local keys only)
- **Builds on**: FX-019 (strobe safety envelope, ADR-0011), FR-072 (Reduce flashing), ACC-001 (Reduce
  Motion, ACC-001-R5), ACC-002 ("May flash" policy), FX-001 (glow), MOD-001/MOD-002 (registry and
  bindings), SHD-002 (graph speed cap), CMP-001/CMP-014 (composite flash guards), FILE-005 (backup)
- **Number**: 0049, the next above the highest taken (0047 FX-002, 0048 FILE-011); 0045 and 0046 stay
  unused, as do 0015, 0016, 0025, 0026 and 0031.

## Context

The roadmap asks to "store per-user limits for flash, motion intensity and haptics locally", accepted when
"applying profile clamps affected parameters before render". The audit (spec Baseline) found every limit
already present but scattered: FX-019's envelope chosen per frame by a Reduce flashing Bool in four
consumers, the 4.0/s bar slew, ACC-002's preset policy, glow ranges, MOD-002 modulation resolved in the
native host, SHD-002's speed cap, and no haptic output at all.

## Decision

1. **Model.** `SensorySafetyProfile` (Standard, Reduced, Strict, Custom) and `SensorySafetyLimits`
   (flashes per second 1…3, rise limit per second or none, intensity limit 0…1) live in the FlashSafety
   package next to `FlashEnvelopeConfiguration`. The flash limit *is* FX-019's configuration (transition
   budget 2f, `riseRatePerSecond`); there is no second limiter and no threshold change.
2. **One clamp.** `SafetyClamp` is built on the main actor from the profile and the effective Reduce
   flashing setting, and handed to every frame resolver: `NativeSpectrumHost.resolveEffectiveGlow()`
   (after MOD-002's `value(for:manual:)`: the excursion scaled by the limit, then the glow capped at
   limit × 1.0, before `BloomEffect.parameters` and the generator's luminance model), the host's
   `VisualFrameContext.flashLimits`, `ANGLERenderer`/`GLESRenderer.flashLimits` (projectM's GLSL envelope),
   `Compositor`/`SceneTransitionBus.flashLimits` (the final composite guard for camera, photo, video and
   text), and `GeneratorGraphLayer.intensityLimit` (speed before `GraphMotion.advance`). The coordinator's
   `applySafety` is the only writer.
3. **Precedence.** Per limit the stricter value wins. The effective Reduce flashing setting (the stored
   choice, else the system Reduce Motion setting) floors the flash part at Reduced's (today's
   `.reduceFlashing`). Reduce Motion alone never touches the intensity limit, so ACC-001-R5 stays true. A
   profile whose flash part is stricter than Standard turns on everything Reduce flashing governs (bar
   slew, ACC-002's flagging, OUT-010's restore fade) without writing the user's stored FR-072 choice.
4. **Standard bit identity.** `flashLimitsOverride` is nil whenever the configuration equals the
   renderer's own `forReduceFlashing(reducesFlashing)` (Standard and Reduced), and every cap returns its
   input untouched at intensity limit 1. Standard therefore runs exactly today's code paths.
5. **projectM.** Preset motion (zoom, rotation, warp) is per-preset engine equations the app does not
   resolve; what applies is the envelope at the profile's limits and ACC-002's policy. No engine patch.
6. **Haptics.** None exist; no control is offered. Future haptic output must read the profile first.
7. **Storage.** Four local `settings.sensorySafety.*` keys: in `ALLOWED_KEYS`, cleared by the UI-test
   reset, included in the FILE-005 backup; never in scenes, cues, MIDI, OSC or modulation.

## Consequences

- A binding or a scene can never push a parameter past the viewer's limit; a scene can never loosen it.
- Strict's tighter envelope reaches every renderer through one optional value; the GPU kernels already
  read every configuration field, so they need no change.
- SHD-001 materials and any future speed or oscillator parameter must take the clamp the same way when
  the app composes them (none does today).

## Alternatives rejected

- Clamping in the settings UI (bindings and restored scenes bypass it).
- Clamping inside `AudioFeatureModulator` (unbound values escape; the registry is shared with scene
  validation).
- Reduce Motion flooring the intensity limit (silently changes every Reduce Motion user's visuals and
  amends ACC-001-R5).
- A separate "sensory" limiter beside FX-019 (two definitions of a flash).
