# Quickstart: VIS-005 Radial Waveform

1. Package (host and Linux shape):
   `swift test --package-path Packages/VisualGenerators --filter RadialWaveform`
   `swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter RadialWaveform`
   Expect: seam ratio ≤ 1.5 (≫ 1.5 without the taper), DC ±0.5 and silence radii, determinism, envelope within budget.
2. Goldens: `swift test --package-path Packages/RenderGoldens --filter RadialWaveformGoldenTests`
   (record once with `GOLDEN_RECORD=1`; simulator with `TEST_RUNNER_GOLDEN_RECORD=1` and
   `-only-testing:RenderGoldensTests/RadialWaveformGoldenTests`).
3. App: `xcodegen generate`, build-for-testing on "VIS5 iPhone 17", then
   `-only-testing:projectM-iOSTests/RadialWaveformAppTests` and
   `-only-testing:projectM-iOSUITests/RadialWaveformUITests` (< 30 s).
4. Device (`{device}`): on D1 with music, choose Radial Waveform and check frame time in the performance overlay.
