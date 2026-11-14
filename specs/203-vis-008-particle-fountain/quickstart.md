# Quickstart: VIS-008 Particle Fountain

1. Package (host and Linux shape):
   `swift test --package-path Packages/VisualGenerators --filter ParticleFountain`
   `swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter ParticleFountain`
   Expect: fixed seed + event log replayed twice bit-identical and with 60 Hz, 30 Hz and irregular frames within 1e-9; ballistic closed form; bounds; Reduce Motion; envelope within budget.
2. Golden: `swift test --package-path Packages/RenderGoldens --filter ParticleFountainGolden`
   (record once with `GOLDEN_RECORD=1`; simulator with `TEST_RUNNER_GOLDEN_RECORD=1`).
3. App: `xcodegen generate`, build-for-testing on "VIS8 iPhone 17", then
   `-only-testing:projectM-iOSTests/ParticleFountainAppTests` and `-only-testing:projectM-iOSUITests/ParticleFountainUITests` (< 30 s).
4. Device (`{device}`): on D1 with music, choose Particle Fountain, check bursts follow onsets, the arcs, Reduce Motion, and the frame time in the performance overlay.
