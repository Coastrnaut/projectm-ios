# ADR-0057: Several Bindings per Parameter, Folded in List Order with a Clamp after Each; ACC-012 Last

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: MOD-011 (`specs/178-mod-011-mix-modes`; contract `contracts/mix-order.md`)
- **Constitution**: VII (real-time safety: bounded, allocation-free per frame), X (evidence), FR-072 /
  ACC-012 (sensory safety stays last)
- **Amends**: MOD-002 (one binding per parameter: `bind` replaced the target's binding) and SCN-001's
  `duplicateBindingTarget` rule (a second binding on a bound target was rejected); ADR-0028's issue
  list is otherwise unchanged

## Context

MOD-011 asks to "combine manual, audio and LFO sources via replace, add and multiply", accepted when
"order and clamping are documented and unit-tested". MOD-002 already had the three mix modes, but each
combined one binding with the manual value, and a parameter could have only one binding, so audio and an
LFO could never act on the same parameter. The order existed only implicitly in one function.

## Decision

1. **Layers**: a parameter may have up to 4 bindings (32 in all). `AudioFeatureModulator.addLayer`
   appends one; `bind` keeps MOD-002's meaning (one binding, replacing all of the target's layers in the
   first one's place); `unbind` removes all layers.
2. **Order**, for one parameter each frame:
   1. Base b: the MIDI-003 live value while one exists, else the manual value (Settings, MOD-010 macro,
      snapshot recall, undo). Modulation never writes it. (Unchanged.)
   2. Bindings in list order (the order added; the scene's `$.bindings` order), r₀ = b. Each binding's
      mapped value is mᵢ = range(curve(envelope(source))) (MOD-002 to MOD-005; LFOs are `audio.lfo.<n>`
      sources, MOD-007):
      - replace: rᵢ = mᵢ
      - add: rᵢ = rᵢ₋₁ + mᵢ (mᵢ within ± the parameter's span)
      - multiply: rᵢ = rᵢ₋₁ × mᵢ (mᵢ within 0…1)
      - a non-finite result keeps rᵢ₋₁.
   3. **Clamp to the registry range after every binding.**
   4. Integer parameters: round half away from zero and snap to the step, once, at the end.
   5. ACC-012, last: e = b + (r − b) × intensity limit, then the target's cap (glow intensity ≤ limit).
3. **Formulas are MOD-002's**: no depth parameter; the output range is the depth. One binding gives
   bit-identical results to MOD-002 (tested over 540 + 60 cases).
4. **Scenes**: restore applies up to 4 bindings per parameter in document order; a fifth, or an SHD-009
   expression on a later layer, is `duplicateBindingTarget` (kept verbatim). Capture writes a
   parameter's expression on its first binding only. No format version change.
5. **Where it lives**: `ModulationMixOrder` (ParameterGraph) is the step; `AudioFeatureModulator`
   folds; `GlowModulationOrder` (VisualParameters) is the glow's whole order including ACC-012, called by
   the native host. The UIX-003 inspector numbers layered bindings and shows the order in one line.

## Alternatives considered

- **Fixed order by mode** (replace, multiply, add): cannot express "offset, then scale"; hides intent.
- **Clamp only at the end**: an overflow could be pulled back by a later multiply to a value no single
  step reaches; per-step clamping saturates predictably.
- **Depth/lerp forms** (replace = lerp(r, m, depth)): would add a field and change stored ranges' meaning.
- **Most recent of MIDI and manual as the base**: needs time stamps on every write path; today's rule
  (MIDI live value while one exists) is kept.

## Consequences

- Older app versions read a scene with layers as before: later layers are `duplicateBindingTarget`,
  kept verbatim, so nothing is lost on a round trip through them.
- Per frame the modulator still scans at most 32 slots and does at most 4 steps per parameter.

## Evidence

`ModulationMixOrderTests` (acceptance table in two list orders with bound-hitting steps, integer
rounding, limits, bit identity, determinism), `GlowModulationOrderTests` (ACC-012 last, Linux-built
package), `SceneLayeredBindingTests` (round trip, fifth rejected), `ModulationMixOrderAppTests` (app host).
