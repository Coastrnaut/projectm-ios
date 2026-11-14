# Contract C1: accessible parameters (ACC-005)

## C1.1 Modifier

```swift
func accessibleParameter(_ spec: AccessibleParameterSpec, target: ParameterTarget,
                         didStep: @escaping @MainActor () -> Void = {}) -> some View
```

Applies, in order: `accessibilityElement(children: .ignore)` (one element of our own; research D1),
`accessibilityLabel(spec.label)`, `accessibilityValue(spoken)`,
`accessibilityIdentifier(spec.id)`, `accessibilityAdjustableAction`. An adjustment computes
`ParameterStepper.step(target.get(), direction, spec)`; when it moved, `target.set(result.value)` then
`didStep()`;
when it could not move, it announces the end text (C1.3) on lane `parameter`. A disabled view is not
adjusted.

## C1.2 Spoken values (exact strings, en)

| unit | value | text |
|---|---|---|
| percent(0) | 0.5 | `50 percent` |
| percent(1) | 0.025 | `2.5 percent` |
| signedDecibels | 6 / 0 / −1 / −12 | `plus 6 decibels` / `0 decibels` / `minus 1 decibel` / `minus 12 decibels` |
| decibelsFullScale | −50 | `minus 50 decibels full scale` |
| milliseconds | 180 / 1 | `180 milliseconds` / `1 millisecond` |
| seconds | 1.5 / 0.25 | `1.5 seconds` / `0.25 seconds` |

## C1.3 End announcements

`Maximum, <spoken value>` and `Minimum, <spoken value>`, kind `parameter`, through
`AccessibilityAnnouncer.announce` (window 1 s, identical repeat dropped within 2 s).

## C1.4 Unchanged

Accessibility identifiers and labels of all ten sliders (XCTest now reports them as "other" elements,
not sliders: research D1); visible readouts ("+6 dB", "−50 dBFS",
"180 ms", "50%", "1.5 s").
