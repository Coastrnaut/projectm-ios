# Contract: MOD-011 mix order

## O1 Evaluation order for one parameter (each frame)

1. **Base** b: the MIDI-003 live value while one exists, else the manual value.
2. **Layers** in binding list order, r₀ = b. For layer i: mᵢ = range(curve(envelope(source))) (MOD-002 to
   MOD-005, MOD-007 for `audio.lfo.<n>`), then
   - replace: rᵢ = mᵢ
   - add: rᵢ = rᵢ₋₁ + mᵢ
   - multiply: rᵢ = rᵢ₋₁ × mᵢ
   - a non-finite result: rᵢ = rᵢ₋₁
   - rᵢ = min(max(rᵢ, minimum), maximum) (registry range).
3. **Integer** parameters: round half away from zero, snap to the step (once).
4. **ACC-012**: e = b + (r − b) × intensityLimit, then the target's cap (glow intensity ≤ limit × 1).

One layer: bit-identical to MOD-002.

## O2 Limits

- 4 layers per parameter, 32 bindings in all. `addLayer` beyond 4 throws `tooManyLayers`; nothing changes.

## O3 Scenes

- Restore: bindings in document order; the 2nd–4th on a parameter are layers; a 5th, or a later layer with an
  expression, is `duplicateBindingTarget` at `$.bindings[i].target` (or `.expression`), kept verbatim.
- Capture: the expression of a parameter is written on its first binding only.
