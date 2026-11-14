# Data Model: MOD-004 Curve Mapping

## MappingCurve (ParameterGraph; `Sendable`, `Hashable`)

| Case | Parameter | Valid when |
|---|---|---|
| `linear` | — | always |
| `easeIn(exponent:)` | p | finite, 1 < p ≤ 8 |
| `easeOut(exponent:)` | p | finite, 1 < p ≤ 8 |
| `easeInOut(exponent:)` | p | finite, 1 < p ≤ 8 |
| `logarithmic(strength:)` | k | finite, 0 < k ≤ 1000 |
| `exponential(strength:)` | k | finite, 0 < k ≤ 1000 |
| `piecewise([CurvePoint])` | interior points | ≤ 8 points; finite; 0 < x < 1, strictly increasing; 0 ≤ y ≤ 1, non-decreasing |

Operations: `apply(_:) -> Double` (contract K1-K4), `validationProblem: String?`, `isValid`,
`isLinear` (linear or an empty piecewise), `kindName`, `textForm` / `init?(textForm:)` (K6).
Constants: `maximumPoints = 8`, `exponentRange`, `strengthRange` limits.

## CurvePoint (ParameterGraph; `Sendable`, `Hashable`)

`x: Double`, `y: Double`.

## AudioFeatureBinding (MOD-002) — changed

`+ curve: MappingCurve` (init parameter, default `.linear`). Refusal `+ invalidCurve(ParameterID,
reason: String)` checked after the envelope in contract C2's order.

## ExpressionMapping (SHD-009) — changed

`+ curve: MappingCurve` (default `.linear`), applied between `position` and interpolation.

## SceneBinding (SCN-001) — changed

`+ curve: MappingCurve` (default `.linear`). Stored as the optional `curve` object (D5); an
unreadable stored curve stays in `extra["curve"]`.

## SceneIssue.Code — changed

`+ unsupportedCurve` (warning; repair group "invalid mappings", action "drop invalid mappings",
"kept in the scene but has no effect").
