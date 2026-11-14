# Research: MIDI-004 MIDI CC Scaling

## MIDI-004-D1: Order of inversion and curve

- **Decision**: position = clamp(value / 127); inverted → 1 − position; then the curve; then MOD-003
  interpolation from the parameter's minimum to its maximum.
- **Rationale**: inverted(v) = normal(127 − v) exactly (1 − v/127 = (127 − v)/127 within rounding; both ends
  exact), so Invert means "the knob runs the other way" and the curve keeps its shape relative to the
  parameter: a logarithmic curve still spends its resolution near the parameter's minimum. Ends: 1 − 0 = 1
  and 1 − 1 = 0 exactly, and MOD-004 pins curve(0) = 0 and curve(1) = 1, and MOD-003 is exact at 0 and 1, so
  the acceptance holds for every curve.
- **Alternatives**: invert after the curve (1 − curve(x)), equivalent to swapping the range ends: it
  moves the fine resolution to the other end of the parameter when inverting. Swapping the interpolation
  ends (`from: maximum, to: minimum`) is the same as after-curve.

## MIDI-004-D2: Stored form

- **Decision**: `cc:<ch>:<num>=<id>` then `;curve=<MOD-004 textForm>` (only when not linear, or the kept
  unreadable text), then `;invert=1` (only when inverted), then unknown segments verbatim in order.
  Reading: split the part after `=` on `;`; the first piece is the ID; empty pieces are skipped; the first
  `curve=` and the first `invert=` are known; repeated known keys are dropped; anything else is kept.
- **Rationale**: a default mapping writes the identical MIDI-003 line (old and new versions read each
  other); MOD-004's text never contains `;` or `=` (contract K6); keeping unknown segments lets a later row
  (sub-range, pickup) add options that survive this version's save.
- **Alternatives**: JSON per line (a format change for MIDI-003 readers); a separate options key (two
  lists to keep in step, two backup keys).

## MIDI-004-D3: Unreadable curve text

- **Decision**: text that `MappingCurve(textForm:)` rejects, or whose curve fails `validationProblem`, gives
  Linear for values, is kept as `unreadableCurveText` and written back unchanged; the row says "Curve not
  readable; using Linear." Choosing a preset clears it.
- **Rationale**: MOD-004 rejects (never repairs) invalid curves at boundaries; keeping the text preserves a
  newer version's curve; Linear is the MIDI-003 behaviour, so nothing surprising happens.

## MIDI-004-D4: Presets

- **Decision**: Linear, Ease in `easeIn(2)`, Ease out `easeOut(2)`, Logarithmic `logarithmic(9)`. A stored
  curve equal to none of them shows as "Custom" (kept until a preset is chosen).
- **Rationale**: the brief's four; exponent 2 and strength 9 are MOD-004's examples (valid, moderate).

## MIDI-004-D5: Options follow the parameter

- **Decision**: `bind(key, to: target)` gives the new binding the options of the target's previous binding
  (if any), else the defaults. A control moved away leaves its old options with the binding that was
  removed.
- **Rationale**: a curve describes how a parameter should respond (fine glow control), not the knob; a
  relearn to fix a wrong knob should not lose it.

## MIDI-004-D6: Preview

- **Decision**: a SwiftUI `Path` through 33 samples of `options.position` (0…1 both axes), drawn in a fixed
  frame, no animation, with an accessibility label describing curve and direction.
- **Rationale**: uses the exact value function, cheap, static (motion policy), and VoiceOver users get the
  same information in words.
