# Quickstart: VIS-007 Mandala Symmetry

1. Package (host and Linux shape):
   `swift test --package-path Packages/VisualGenerators --filter Mandala`
   `swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter Mandala`
   Expect: N = 4 → 8 doubles sectors and vertices, rotated copies within 1e-9, repeat bit-identical; mirror; silence base shape; rotation cap and Reduce Motion; envelope within budget.
2. Golden: `swift test --package-path Packages/RenderGoldens --filter MandalaGoldenTests`
   (record once with `GOLDEN_RECORD=1`; simulator with `TEST_RUNNER_GOLDEN_RECORD=1`).
3. App: `xcodegen generate`, build-for-testing on "VIS7 iPhone 17", then
   `-only-testing:projectM-iOSTests/MandalaAppTests` and `-only-testing:projectM-iOSUITests/MandalaUITests` (< 30 s).
4. Device (`{device}`): on D1 with music, choose Mandala, check the petals follow the music, the slow turn, and the frame time in the performance overlay.
