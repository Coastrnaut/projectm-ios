# Quickstart: MOD-010 Parameter Macro

1. Package tests (host; Linux in CI):
   `swift test --package-path Packages/ParameterGraph --filter ParameterMacroTests` and
   `swift test --package-path Packages/SceneFormat --filter SceneMacroTests` — the acceptance macro
   (intensity easeIn, radius log inverted, bars enum) at 0, 0.25, 0.5, 1 equals each target's curve and
   range, before and after a scene round trip.
2. App unit tests on the private simulator: `-only-testing:projectM-iOSTests/ParameterMacroAppTests`
   (settings written, undo in one step, autosave round trip).
3. UI test: `-only-testing:projectM-iOSUITests/ParameterMacroUITests` (launch with `-uitestSeedMacro`, open
   Settings › Macros, move the slider, the target labels change; under 30 s).
