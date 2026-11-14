# Research: ANL-003 Spectral Smoothing

## ANL-003-D1: Where the smoothing sits

- **Decision**: On the display side, in `NativeSpectrumHost`'s frame callback, after
  `LiveBandOutput.readLatest` and before the generator; per band, on the normalized 0…1 values.
- **Rationale**: The roadmap acceptance is about time ("by attack setting"), and what the user sees
  is display frames. Between analysis frames (hop 512 at 44.1 kHz ≈ 11.6 ms) the host repeats the
  last vector; a display-side follower turns those steps into a continuous approach at any refresh
  rate (60 or 120 Hz). Onset detection (ANL-004) and beat tracking work on raw spectra inside the
  pipeline and are untouched; bus subscribers (tap tempo, future kick/snare detectors) keep raw
  bands.
- **Alternatives**: in `AnalysisPipeline` at the analysis hop (Δt = hop / sample rate,
  deterministic): changes every subscriber's input and still steps on screen; in each generator:
  duplicates code in three generators and their layouts.

## ANL-003-D2: The rule

- **Decision**: y ← y + a·(x − y), a = 1 − exp(ln(0.1)·Δt/τ) (τ = attack if x > y else release;
  τ = 0 → a = 1). Coefficients computed once per frame in Double; state Float.
- **Rationale**: After frames with total time T the remaining fraction of a step is
  exp(ln 0.1 · T/τ), exactly 0.1 at T = τ regardless of how T is split, so the 90 % crossing is
  frame-rate independent and lies within one frame after τ. Choosing the direction per band per
  frame makes rise and fall independent.
- **Alternatives**: a fixed per-frame factor (frame-rate dependent); a linear slew (that is
  Reduce flashing's VIS-001-R10 rule, a safety bound, not a smoother); time constant τ meaning 63 %
  (the roadmap names 90 %).

## ANL-003-D3: Resets and invalid input

- **Decision**: Snap state = input on the first update, after `reset()`, when the band count or
  the capture-session generation changes. A non-finite input band holds its state (0 if snapping).
  Δt ≤ 0 or non-finite: a = 0 for non-zero τ (no progress), a = 1 for τ = 0. No Δt clamp.
- **Rationale**: No ramp from zero on start or from an old session's picture; the host also
  resets on resume, mirroring the Reduce-flashing limiter (VIS-001). Holding on NaN never invents
  light. The exponential is exact for any positive Δt, so clamping would only slow recovery after
  a hitch.

## ANL-003-D4: Defaults, bounds and UI

- **Decision**: Default 0/0 (Instant) — bit-identical to today. Choices Attack 0/25/50/100 ms,
  Release 0/100/250/500 ms as segmented pickers in a Smoothing section below the Visual section, for the circular and linear spectra (inside the Visual section they pushed its fallback footer off screen).
  Library bounds 0…2 s. Keys `settings.spectrum.attack`, `settings.spectrum.release` (Int ms).
- **Rationale**: "Defaults keep today's look"; discrete choices match the oscilloscope's Window
  row and fit a segmented control on a narrow iPhone. Fast attack / slower release is the common
  meter ballistic, so the offered ranges differ.
- **Alternatives**: sliders (finer but noisier UI, harder to test); a non-zero default (changes
  today's look); parameter catalog / scene entries (scene format change; separate row).

## ANL-003-D5: Existing motion is kept, not replaced

- **Decision**: No existing code smooths bands (audit). Reduce flashing's slew (VIS-001-R10), the
  linear spectrum's peak caps (VIS-002-R6) and FX-019's envelope stay and act after smoothing.
  MOD-002 bindings keep raw bands. Camera/Photo/Video/Text hosts keep raw bands (follow-up).

## ANL-003-D6: Linux and type-checking

- **Decision**: Pure Swift with `Foundation.exp`/`log` (available on Linux); no Accelerate (a
  128-element branchy loop gains nothing from vDSP). Arithmetic in short typed `let` steps.
