# Contract: MappingCurve (MOD-004)

`public enum MappingCurve` in `Packages/ParameterGraph/Sources/ParameterGraph/MappingCurve.swift`.

## K1 — Input

`apply(x)` first reads x as MOD-003 reads a position: non-finite (NaN, ±∞) → 0, then limited to
0…1. So −1 → 0, 2 → 1, −0 → 0.

## K2 — Ends

For every curve, valid or not: `apply(0) == 0` and `apply(1) == 1` exactly.

## K3 — Bounded, monotonic, deterministic

For every curve, valid or not, and every input: `0 ≤ apply(x) ≤ 1`; `x₁ ≤ x₂ ⇒ apply(x₁) ≤
apply(x₂)`; the same input always gives the same bits. `apply` reads no clock, randomness or
shared state and allocates nothing.

## K4 — Shapes (valid curves)

Formulas in research MOD-004-D1. Linear returns x unchanged (bit-identical, D4). Invalid curves
act on limited parameters (a non-finite exponent or strength acts as linear) and skip points that
break the piecewise rules; only the first 8 points are considered.

## K5 — Validation

`validationProblem` is nil for a valid curve, otherwise a readable sentence naming the first fault
(research D3). `AudioFeatureModulator.bind` refuses an invalid curve with
`AudioFeatureBindingError.invalidCurve(target, reason:)`, description
`the curve bound to "<id>" is invalid: <reason>`; the bindings are unchanged.

## K6 — Text form (for MIDI-004)

| Curve | Text |
|---|---|
| linear | `linear` |
| ease-in p | `easeIn:<p>` |
| ease-out p | `easeOut:<p>` |
| ease-in-out p | `easeInOut:<p>` |
| logarithmic k | `log:<k>` |
| exponential k | `exp:<k>` |
| piecewise | `piecewise:<x>,<y>/<x>,<y>…` (`piecewise:` when empty) |

Numbers are `Double.description`. `MappingCurve(textForm:)` returns the same curve for every form
written by `textForm`, nil for anything else; it does not validate ranges. The text never contains
`;` or `=`. MIDI-004 line: `cc:<ch>:<num>=<parameter ID>;curve=<text>`.

## K7 — Binding pipeline

`AudioFeatureModulator` resolves `mapping.interpolate(curve.apply(signal))`, then mixes and clamps
as before (MOD-002); ACC-012's clamp in the app follows. `ExpressionMapping.map` is
`interpolate(curve.apply(position))`.

## K8 — Scene storage

`$.bindings[i].curve` (optional): `{"kind":"easeIn"|"easeOut"|"easeInOut","exponent":<n>}`,
`{"kind":"logarithmic"|"exponential","strength":<n>}`,
`{"kind":"piecewise","points":[{"x":<n>,"y":<n>},…]}`, `{"kind":"linear"}`. Written only for
non-linear curves. Unreadable → kept verbatim, binding rejected with `unsupportedCurve` (warning)
`Binding <i> uses a curve this version cannot read; it is kept but not applied.` Readable but
invalid → binding rejected with `invalidBinding` carrying the K5 description.
