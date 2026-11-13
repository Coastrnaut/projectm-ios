# Contract: audio feature binding (MOD-002)

The public surface of `ParameterGraph`'s binding model, for later rows (MOD-003 to MOD-014, scenes,
MIDI/OSC) and the app.

## C1 Sources

- `AudioFeatureSource.band(i)` (0 ≤ i ≤ 127), `.bandMean`, `.onset`, `.beatConfidence`.
- `source.id` / `AudioFeatureSource(id:)`: `audio.band.<i>`, `audio.bandMean`, `audio.onset`,
  `audio.beatConfidence`; anything else (leading zeros, signs, out-of-range index) → nil.
- `source.value(in: frame) -> Double` in 0…1 for normalized inputs; missing or non-finite → 0.

## C2 Binding validation (`AudioFeatureModulator.bind(_:) throws(AudioFeatureBindingError)`)

Checked in this order; the first failure is thrown, state unchanged:

1. target registered → else `unknownTarget` (Reduce flashing is never registered);
2. kind continuous or integer → else `notNumeric`;
3. policy modulatable → else `notModulatable`;
4. mix mode in the policy's modes → else `mixModeNotAllowed`;
5. band index 0…127 → else `bandIndexOutOfRange`;
6. input range finite with minimum < maximum → else `invalidInputRange`;
7. output ends finite and inside the mode's bounds (replace `[min, max]`, add `±(max − min)`,
   multiply `0…1`) → else `outputOutOfRange`;
8. envelope times finite and in 0…60 s → else `invalidEnvelope`;
9. fewer than 32 other bindings → else `tooManyBindings`.

A valid binding for an already bound target replaces it (signal 0, clock reset).

## C3 Evaluation

- `advance(frame:timeNanoseconds:)`: per slot, Δt = 0 on its first call or when time does not
  increase, else min(Δt, 0.25 s); `x = clamp((f − inMin)/(inMax − inMin), 0, 1)`; `τ` = attack if
  `x > s` else release; `s = x` when `τ = 0`, else `s += (x − s)(1 − exp(−Δt/τ))`.
- `value(for:manual:)`: unbound → `manual` unchanged (bit for bit). Bound → `m = (1 − s)·out0 +
  s·out1`; replace `m`, add `manual + m`, multiply `manual · m`; clamp to range; integers round half
  away from zero, then snap to the step from the minimum (as the store does).
- No allocation, lock or wall clock in `advance` and `value(for:…)`. Never call from an audio
  callback. One owner thread at a time.

## C4 Unbind

- `unbind(id) -> Bool` (false when not bound); `unbindAll()`. After unbinding, `value(for:manual:)`
  returns `manual`. Modulation never writes to a `ParameterStore`.

## C5 App (Debug only)

- Launch argument `-uitestBindGlowToBass`: binds `audio.band.0` → `effect.bloom.intensity`, replace
  0…1, no envelope, when the native host is created.
- Accessibility: `glowModulation` (static text; label and value "bound|unbound, manual X.XX,
  effective Y.YY"), `glowModulationUnbind` (button).
