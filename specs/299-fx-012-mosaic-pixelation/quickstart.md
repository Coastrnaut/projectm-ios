# Quickstart: FX-012 Mosaic Pixelation

1. Model (any OS): `swift test --package-path Packages/Compositor --filter MosaicModelTests`.
2. GPU acceptance (Mac): `swift test --package-path Packages/Compositor --filter MosaicCompositeTests` (off and size 1
   bit-identical, 8 × 8 blocks uniform and discrete, hexagon cells uniform, reference match).
3. Scenes: `swift test --package-path Packages/SceneFormat --filter SceneEffectChainTests`; RenderGoldens
   `EffectChainSceneTests`.
4. App (own simulator): `MosaicSettingTests`, `MosaicUITests`.
5. Device `{device}` (FX-012-T18): on D1, Photo visual, Mosaic at 8 and 64 in both shapes: blocks are flat and
   discrete; note the frame rate with and without it.
