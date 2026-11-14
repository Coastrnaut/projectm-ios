# Research: MOD-015 Envelope Follower Bank

- **MOD-015-D1 Reuse MOD-005's envelope.** Decision: each profile is an `AudioFeatureEnvelope` (attack/release τ,
  `x + (s₀ − x)·e^(−t/τ)`). The bank precomputes the two coefficients `1 − e^(−Δt/τ)` per profile per frame and
  applies the same update and clamps as `AudioFeatureEnvelope.step`; tests check agreement with `step` to 1e-12.
  Rationale: one definition of the one-pole envelope in the codebase; 6 `exp` per frame instead of 384.
  Alternatives: ANL-003 `BandSmoother` (rejected: AnalysisFeatures, display-side, τ defined at 90 %, a
  dependency ParameterGraph must not take); calling `step` per envelope (384 `exp`, rejected for cost).
- **MOD-015-D2 Time constants.** fast 10/80 ms, medium 80/350 ms, slow 400/1600 ms (attack/release τ). 10–90 %
  rise times 22 ms, 176 ms, 879 ms. Rationale: fast follows hits within about one 60 fps frame, medium follows
  phrases, slow follows sections; ≥ 4× spacing keeps them distinct. Alternatives: user-set times (deferred: a
  binding's MOD-005 envelope already gives per-route times).
- **MOD-015-D3 Clock.** The frame's display time (UInt64 ns), Δt rules of `AudioFeatureModulator` (first 0,
  non-increasing 0, cap 0.25 s). Chunking invariance holds because `(1 − a₁)(1 − a₂) = e^(−(Δt₁+Δt₂)/τ)` while the
  direction (attack/release) does not change within a constant-input interval and each step is under the cap.
- **MOD-015-D4 Exposure.** A new source case `bandEnvelope(band, profile)` with ID
  `audio.bandEnvelope.<profile>.<band>`, values passed borrowed in `AudioFeatureFrame.bandEnvelopes`
  (band-major: `band·3 + profile`), like `lfos` (MOD-007). Rationale: no copy, the frame stays independent of
  the bank, scenes/MOD-013/matrix/inspector all key on `AudioFeatureSource`. The `audio.` prefix keeps older
  versions orphaning the ID (MOD-013) instead of dropping it.
- **MOD-015-D5 No expression opcode.** Expressions do not name band envelopes (precedent MOD-007-D4).
  Rationale: avoids taking an opcode number while ANL-013 (34) is in flight, and a formula wanting smoothing can
  bind the source instead. The compiler's exhaustive switch maps the case to an unreachable constant.
- **MOD-015-D6 Where the bank advances.** In `NativeSpectrumHost.applyModulation`, after its existing early
  return (no bindings and no triggers → nothing runs). Rationale: no cost when idle; state held while idle.
