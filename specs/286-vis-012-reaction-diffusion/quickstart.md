# Quickstart: VIS-012 Reaction Diffusion

1. Host: `swift test --package-path Packages/VisualGenerators --filter ReactionDiffusion` — model, GPU determinism,
   never-NaN, iteration bound, allocation and flash tests (≈ 5 s). On demand: `VIS012_LONG=1` for long CPU runs.
2. Goldens: `swift test --package-path Packages/RenderGoldens --filter ReactionDiffusionGolden` (and the simulator
   via `-only-testing:RenderGoldensTests/ReactionDiffusionGoldenTests`).
3. App: `-only-testing:projectM-iOSTests/ReactionDiffusionAppTests` and
   `-only-testing:projectM-iOSUITests/ReactionDiffusionUITests` on "VIS12 iPhone 17".
4. Device `{device}`: D1, choose Reaction Diffusion with music; patterns grow, bass plants new growth, frame rate holds.
