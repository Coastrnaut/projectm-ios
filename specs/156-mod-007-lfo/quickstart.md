# Quickstart: MOD-007 LFO Sine and Triangle

1. `swift test --package-path Packages/ParameterGraph --filter LFO` — acceptance
   (`testKnownTimeSamplesMatchClosedForm`: quarter periods, irrational and multi-hour times within 1e-9),
   determinism, bounds, safety cap, binding source.
2. `swift test --package-path Packages/SceneFormat --filter SceneLFO` — round trip, legacy shape, issues.
3. App: `xcodegen generate`, build-for-testing on "MOD7 iPhone 17", then
   `test-without-building -only-testing:projectM-iOSTests/LFOBindingAppTests` — an LFO binding drives the glow.
4. Whole suites and the repository checks (see tasks.md polish phase).
