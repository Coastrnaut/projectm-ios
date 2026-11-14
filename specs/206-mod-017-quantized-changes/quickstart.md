# Quickstart: MOD-017 validation

1. `swift test --package-path Packages/PerformanceControl --filter QuantizedChangeQueue` — Beat, Bar and Cue
   acceptance (not before, exactly once at, never after the boundary), latest wins, cancel, fallback, clear.
2. App: build-for-testing on "MOD17 iPhone 17", then
   `test-without-building -only-testing:projectM-iOSTests/ParameterQuantizerAcceptanceTests` — the real write path
   with a synthetic tempo and clock: glow on applies once at the beat; lock at the boundary refuses; cue step applies.
3. `-only-testing:projectM-iOSUITests/QuantizedChangesUITests` — the queued indication appears in the inspector.
4. Repo checks from AGENT_RULES.md.
