# Data Model: ACC-005 VoiceOver Parameter Editing

No stored data is added; every control keeps its existing setting.

## SpokenUnit (enum)

`percent(decimals: Int)`, `signedDecibels`, `decibelsFullScale`, `milliseconds`, `seconds`.

## AccessibleParameterSpec (value type)

| Field | Type | Rule |
|---|---|---|
| id | String | the existing accessibility identifier (unchanged, R9) |
| label | String | the existing accessibility label |
| range | ClosedRange<Double> | from the registry (glow) or the owning setting |
| step | Double | > 0; the control's own snapping step or a multiple of the registry hint (≤ 25 steps end to end) |
| unit | SpokenUnit | |

`withRange(_:)` returns a copy for the loop sliders, whose upper bound is the video's duration.

## ParameterTarget (value type, main actor)

`get: () -> Double`, `set: (Double) -> Void` over the real setting or coordinator.

## ParameterStepResult

`value: Double` (clamped grid value), `atEnd: Bool` (no move was possible), `end: maximum | minimum | nil`.

## Catalog (10 specs)

| id | label | range | step | unit |
|---|---|---|---|---|
| glowIntensitySlider | Intensity | registry 0…1 | 0.05 (hint 0.01 × 5) | percent(0) |
| glowRadiusSlider | Radius | registry 0.005…0.06 | 0.005 (hint 0.001 × 5) | percent(1) |
| glowThresholdSlider | Threshold | registry 0.1…1 | 0.05 (hint 0.01 × 5) | percent(0) |
| textSizeSlider | Size | 0.03…0.25 | 0.01 | percent(0) |
| textOutlineSlider | Outline | 0…0.15 | 0.01 | percent(0) |
| inputTrimSlider | Input trim | −12…24 | 1 | signedDecibels |
| noiseGateThresholdSlider | Gate threshold | −80…−20 | 1 | decibelsFullScale |
| latencyOffsetSlider | Visual delay | 0…250 | 5 | milliseconds |
| videoLoopIn | Loop in | 0…duration | 0.1 | seconds |
| videoLoopOut | Loop out | 0…duration | 0.1 | seconds |
