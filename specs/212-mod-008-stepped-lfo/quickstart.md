# Quickstart: MOD-008 Stepped LFO

1. `swift test --package-path Packages/ParameterGraph --filter SteppedLFOTests` — acceptance (same seed and
   timebase, three frame chunkings, identical levels; different seed differs), square boundaries, glide,
   synced continuity, Reduce flashing.
2. `swift test --package-path Packages/SceneFormat --filter SceneLFOTests` — round trip of shape, duty, seed,
   glide; invalid values reported; old scenes byte-identical.
3. App: `xcodebuild test-without-building -only-testing:projectM-iOSTests/LFOBindingAppTests` on the private
   iOS 27.2 simulator — a sample-and-hold oscillator on the glow holds its levels.
