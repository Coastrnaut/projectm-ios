# Quickstart: MOD-006 Threshold Trigger

1. `swift test --package-path Packages/ParameterGraph --filter ThresholdTrigger` — acceptance
   (`testNoiseAroundThresholdProducesNoTriggerStorm`: at most 1 trigger in 10 s of seeded noise),
   pulse trains, edges.
2. `swift test --package-path Packages/SceneFormat --filter SceneTrigger` — round trip, legacy shape,
   issues.
3. App: `xcodegen generate`, build-for-testing on "MOD6 iPhone 17", then
   `test-without-building -only-testing:projectM-iOSTests/ThresholdTriggerAppTests` — a kick-driven
   trigger performs Next cue once per kick.
4. Whole suites and the repository checks (see tasks.md polish phase).
