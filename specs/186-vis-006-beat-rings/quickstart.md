# Quickstart: VIS-006 Beat Pulse Rings

1. Package (host and Linux shape):
   `swift test --package-path Packages/VisualGenerators --filter BeatRing`
   `swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter BeatRing`
   Expect: four beats → four independent rings, zero after the last life; cap 16, rate ≤ 3/s under Reduce flashing; determinism; envelope within budget.
2. Golden: `swift test --package-path Packages/RenderGoldens --filter BeatRingGoldenTests`
   (record once with `GOLDEN_RECORD=1`; simulator with `TEST_RUNNER_GOLDEN_RECORD=1`).
3. App: `xcodegen generate`, build-for-testing on "VIS6 iPhone 17", then
   `-only-testing:projectM-iOSTests/BeatRingsAppTests` and `-only-testing:projectM-iOSUITests/BeatRingsUITests` (< 30 s).
4. Device (`{device}`): on D1 with music, choose Beat Rings, check rings follow the beat and the frame time in the performance overlay.
