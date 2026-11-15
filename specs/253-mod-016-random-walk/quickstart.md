# Quickstart: MOD-016 Random walk modulator

1. `swift test --package-path Packages/ParameterGraph --filter RandomWalkTests` — acceptance (same seed and
   timebase, 60 Hz / 120 Hz / jittery chunkings and seeks give identical values; a different seed differs),
   bounds over dense and 10-hour sweeps, continuity bound, ease, synced continuity, Reduce flashing.
2. `swift test --package-path Packages/SceneFormat --filter SceneLFOTests` — round trip of shape, smoothness and
   seed; invalid smoothness reported; old scenes byte-identical.
3. App: `xcodebuild test-without-building -only-testing:projectM-iOSTests/LFOBindingAppTests` on the private
   iOS 27.2 simulator — a random walk on the glow follows its values.
