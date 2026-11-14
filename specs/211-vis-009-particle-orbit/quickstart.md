# Quickstart: VIS-009 Particle Orbit

1. Package (host and Linux shape):
   `swift test --package-path Packages/VisualGenerators --filter 'ParticleOrbit|VisualParameterCatalog'`
   `swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter ParticleOrbit`
   Expect: settled radius within 1 % of the mapped value, monotone and bounded; binding path; work bound over 600 frames; determinism; envelope within budget.
2. Golden: `swift test --package-path Packages/RenderGoldens --filter ParticleOrbitGolden` (record once with `GOLDEN_RECORD=1`; simulator with `TEST_RUNNER_GOLDEN_RECORD=1`).
3. App: `xcodegen generate`, build-for-testing on "VIS9 iPhone 17", then `-only-testing:projectM-iOSTests/ParticleOrbitAppTests` and `-only-testing:projectM-iOSUITests/ParticleOrbitUITests` (< 30 s).
4. Device (`{device}`): on D1 with music, choose Particle Orbit; the ring swells on kicks, the centre pulses on beats; the performance overlay shows the frame rate within budget.
