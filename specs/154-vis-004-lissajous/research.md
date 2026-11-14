# Research: VIS-004 Lissajous Scope

Audit of 2026-11-14 (commit `1fe5f95c`) and the design decisions. Each decision lists what was
chosen, why, and what was rejected.

## Audit findings

- **Oscilloscope (VIS-003)** is the template: `OscilloscopeLayout` (CPU geometry, preallocated,
  `FlashRegionLayout` for the envelope), `OscilloscopeGenerator` (Metal, `FlatShapePass`), golden in
  `RenderGoldens/GeneratorGoldens/<class>/` under QA-002's rule and QA-003's `ImageDiff`.
- **The oscilloscope reads mono**: `WaveformTap` mixes each frame to (L + R)/2 and publishes 4,096
  samples through `WaveformFrameBuffer`. The stereo pair is not kept anywhere a visual can read.
- **Registering a visual**: `VisualChoice` (raw value stored under `settings.visual`, `isNative`),
  Settings' Visual section lists `allCases` (identifier `visual.<raw>`), `AppCoordinator.nativeSpectrumStyle`
  maps the choice to `NativeSpectrumStyle`, the host builds the generator in `makeGenerator`, scene
  capture skips non-layer visuals in `ShowSceneSnapshot` and `SceneAutosaveCapture`.
- **FX-009 Trails** (`Compositor/MotionFeedback.swift`): decay 0.5^(Δt / h), half-life 0.05…0.5 s
  (default 0.2), ACC-012 cap `limited(by:)`: ≤ intensity limit × 0.5 s, ≤ 0.25 s with Reduce flashing,
  0 → off. The compositor is not in the native host's path.
- **FX-001 glow** follows the generator through `EffectChain`; `downstreamLuminance` feeds the
  envelope. Shared by all native visuals unchanged.
- **ACC-003 palette**: `VisualPalette.color(bar:of:)`; the host applies it to every generator.
- **Motion and flash rules**: `check_motion_policy.py` flags UI animations outside `MotionPolicy`
  (none added here); every native frame passes `FlashSafetyLimiter.gain(for:…)` with the 17-area model.
- **AUD-009** channel selection writes the selected signal into both channels before the tap, so a
  non-Mix selection makes the Lissajous mono.

## Decisions

- **VIS-004-D1 Stereo path**: `WaveformTap` keeps a second rolling history (2,048 interleaved frames)
  and a second `WaveformFrameBuffer` (`stereoOutput`). Rationale: same thread, same pattern, no change
  to the forwarded reads or to the mono history. Rejected: a second tap reader; samples on the
  analysis bus frame.
- **VIS-004-D2 Axes**: X/Y default, Mid/Side option with x = (R − L)/√2, y = (L + R)/√2. Rationale:
  the roadmap names X/Y; Mid/Side is the goniometer convention (mono vertical, left leans left).
- **VIS-004-D3 Drawing**: polyline of rectangles in the shared "over" pass. Rationale: no new
  pipeline; overlaps never exceed one segment's brightness, so the area model (which counts overlaps
  twice) overestimates, never underestimates. Rejected: additive points (new blend state; light
  unbounded by overlap count).
- **VIS-004-D4 Auto gain**: level = max(peak, 0.01), instant rise, 0.5 s hold, 0.5 s release
  half-life, frame durations clamped to 0…0.1 s. Rationale: deterministic, quiet audio fills the view,
  loud transients do not pump. Rejected: per-frame normalization (shape size jitters with every
  window).
- **VIS-004-D5 Persistence**: 8 CPU snapshots of 128 points at half-life/2 spacing, weight
  (0.5^(age/h) − 1/16)/(15/16), reaching 0 and dropped at 4 h (shifted so a retraced ghost fades out without a pop; implementation finding 2026-11-14). Rationale: deterministic and testable on Linux, bounded geometry
  (≤ 1,016 extra segments), counted by the flash model. Rejected: a GPU accumulation texture (GPU-only
  state, a second pass, a texture per size); the compositor's Trails pass (not in this host).
- **VIS-004-D6 Safety caps**: `LissajousConfiguration.persistenceHalfLife(enabled:clamp:)` mirrors
  `MotionFeedback.limited(by:)` with the same numbers (0.2 s nominal). Rationale: one rule for every
  afterglow.
- **VIS-004-D7 Goldens**: `GeneratorGoldens/Lissajous/<class>/`, scenes `lissajous-inphase` and
  `lissajous-quadrature` (440 Hz, amplitude 0.8, X/Y, persistence off), frame 1 of 2 captured, both
  QA-002 resolutions. A folder of its own keeps the oscilloscope's one-scene integrity check intact.
