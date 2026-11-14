# Research: MOD-011 Modulation Mix Modes

## MOD-011-D1: Layers per parameter and their order

- **Decision**: up to 4 bindings per parameter (32 in all), applied in binding list order. `bind` keeps
  MOD-002's meaning (replaces all of the target's bindings with one, in the first one's place); `addLayer`
  appends at the end of the list; `unbind` removes every layer.
- **Rationale**: list order is what scenes already store and what MOD-002 already evaluates; no new ordering
  field. Keeping `bind` unchanged leaves every existing caller and test as is.
- **Alternatives**: a fixed order by mix mode (replace, then multiply, then add) — hides the author's
  intent and cannot express "scale, then offset" vs "offset, then scale"; rejected. Unlimited layers — no
  use case beyond manual + audio + LFO; rejected for a bounded per-frame cost.

## MOD-011-D2: Formulas

- **Decision**: MOD-002's, folded: r₀ = base; replace rᵢ = mᵢ; add rᵢ = rᵢ₋₁ + mᵢ; multiply rᵢ = rᵢ₋₁ × mᵢ, with
  mᵢ = range(curve(envelope(source))). A non-finite step leaves rᵢ = rᵢ₋₁.
- **Rationale**: single-binding results stay bit-identical; MOD-003's output range already is the depth
  (add: ± span; multiply: 0…1 factor).
- **Alternatives**: lerp/depth forms (replace = lerp(r, m, depth)) — would need a new field and change the
  meaning of stored ranges; rejected.

## MOD-011-D3: Clamping

- **Decision**: clamp to the registry range after every step; integers round (half away from zero) and snap
  to the step once at the end.
- **Rationale**: each step sees a valid parameter value; saturation is predictable; for one binding it is
  exactly MOD-002. Rounding intermediates would make small add layers vanish on integer parameters.
- **Alternatives**: clamp only at the end — an add followed by a multiply could pull an overflow back into
  range and give a value no single step could reach; rejected.

## MOD-011-D4: Base value

- **Decision**: the MIDI-003 live value while one exists, else the manual value (Settings, macro, snapshot
  recall, undo). Unchanged from today.
- **Rationale**: no behaviour change; a MIDI value is the performer's most recent hand on that control and
  ends when the mapping is removed. "Most recent of MIDI or Settings" would need time stamps on every write path.

## MOD-011-D5: ACC-012 last, in one tested function

- **Decision**: `GlowModulationOrder.resolve(base:modulator:clamp:)` in VisualParameters: fold → excursion
  scaling (`SafetyClamp.modulated`) → cap (`BloomParameters.limited(by:)`). The host calls it.
- **Rationale**: the host's code was the only place the full order existed; moving it into a package makes
  the "ACC-012 last" part testable on Linux.

## MOD-011-D6: Scenes

- **Decision**: restore accepts up to 4 bindings per parameter in document order; a fifth, or an expression on
  a later layer, is `duplicateBindingTarget` (kept verbatim). Capture writes a parameter's expression on its
  first binding only. No version bump.
- **Rationale**: the same issue code keeps SCN-012 repair and reporting unchanged; older apps reject the extra
  layers but keep them verbatim, so nothing is lost.

## MOD-011-D7: Inspector

- **Decision**: when a parameter has more than one binding, number them "1. …", "2. …" in application order and
  add the line "Order: base, then bindings 1…n, then the sensory safety limit". One binding: unchanged.
