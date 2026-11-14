# Quickstart: PERF-003 Adaptive effect quality

1. Pure logic and Metal plan tests on the host: `swift test --package-path Packages/VisualGenerators --filter EffectQuality`
   (ladder order and hysteresis, Reduced plan invariants, encode counts, strobe fixture at every level).
2. Linux shape: `swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL --filter EffectQualityLadder`.
3. Governor: RenderingTests `QualityGovernorTests` on the feature simulator ("PERF3").
4. Diagnostics: `swift test --package-path Packages/Diagnostics --filter FrameTimingsExport`.
5. App: `EffectQualityAppTests` (host wiring) and `EffectQualityOverlayUITests` (launch with
   `-uitestThermalState serious`, circular spectrum, glow on, overlay on → `effect quality reduced (thermal)`).
6. Device `{device}`: D1, glow on, sustained load until the thermal state reaches serious; the overlay shows
   Reduced at 60 fps cap; export with `perf001`. Simulator results are not performance evidence.
