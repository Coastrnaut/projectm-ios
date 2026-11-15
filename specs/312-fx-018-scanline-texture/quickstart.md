# Quickstart: FX-018 Scanline texture

1. Model (any OS): `swift test --package-path Packages/Compositor --filter ScanlinesModelTests`.
2. GPU acceptance (Mac): `swift test --package-path Packages/Compositor --filter ScanlinesCompositeTests` (off and
   intensity 0 bit-identical, the shader at 0 bit-identical, every spacing 2…16 at several sizes with exact dark rows,
   one factor and measured pitch, vertical, reference match, finite).
3. Scenes: `swift test --package-path Packages/SceneFormat --filter Scanlines`; RenderGoldens
   `ScanlinesSceneGoldenTests`.
4. App (own simulator): `ScanlinesSettingTests`, `ScanlinesUITests`, `EffectChainUITests`.
5. Device `{device}` (FX-018-T16): on D1, Photo visual, Scanlines at spacing 2, 3 and 16 and intensity 100 %: even
   lines, no crawl or flicker; note the frame rate with and without it.
