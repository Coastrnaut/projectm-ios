# Quickstart: FX-008 Radial Blur

1. Model (any OS): `swift test --package-path Packages/Compositor --filter RadialBlurModelTests`.
2. GPU acceptance (Mac): `swift test --package-path Packages/Compositor --filter RadialBlurCompositeTests`
   (focus stable, streak lengths d·s within 1 px, zero bit-identical, reference match).
3. Scenes: `swift test --package-path Packages/SceneFormat --filter SceneEffectChainTests`; RenderGoldens
   `EffectChainSceneTests`.
4. App (own simulator): `RadialBlurSettingTests`, `RadialBlurUITests`.
5. Device `{device}` (FX-008-T18): on D1, Photo visual, Radial blur at 25% with the focus centred and moved: streaks
   radiate from the focus; note the frame rate with and without it.
