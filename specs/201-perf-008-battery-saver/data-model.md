# Data Model: PERF-008

| Entity | Fields | Rules |
|---|---|---|
| `PowerProfile` (String raw) | `standard`, `followLowPowerMode`, `batterySaver` | stored as raw value; unknown → `standard` |
| `PowerBudget` | `maxFramesPerSecond: Int`, `renderScaleCap: Double`, `allowsBackgroundWarmUp: Bool` | standard = 60, 1.0, true; batterySaver = 30, 0.75, false |
| profile → budget | `budget(lowPower:)` | standard → standard; batterySaver → batterySaver; followLowPowerMode → batterySaver iff Low Power on |
| governor result | `QualitySettings` | fps = max(30, min(thermal fps, budget fps)); scale = min(thermal scale, budget scale) |
| UserDefaults | `settings.performance.powerProfile` | preference: FILE-005 included, FILE-011 erased, `-uitestResetNotice` removes |
