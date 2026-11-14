# Quickstart: MOD-009 Tempo-Synced LFO

1. `swift test --package-path Packages/ParameterGraph --filter LFOSync` — acceptance
   (`testQuarterNoteCycleAt120BPMLastsHalfASecond`: 1 beat = 0.5 s, 4 beats = 2.0 s within 1e-9), tempo change
   continuity, fallback, cap, validation.
2. `swift test --package-path Packages/PerformanceControl --filter LFOTempoSource` — manual > confident estimate > fallback.
3. `swift test --package-path Packages/SceneFormat --filter SceneLFO` — sync round trip and issues.
4. App: `xcodegen generate`, build-for-testing on "MOD9 iPhone 17", then
   `test-without-building -only-testing:projectM-iOSTests/LFOBindingAppTests` — a synced LFO follows the tap tempo.
5. Whole touched suites and the repository checks (tasks.md polish phase).
