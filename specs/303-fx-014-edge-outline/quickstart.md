# Quickstart: FX-014 Edge Outline

1. Model (any OS): `swift test --package-path Packages/Compositor --filter EdgeOutlineModelTests`.
2. GPU acceptance (Mac): `swift test --package-path Packages/Compositor --filter EdgeOutlineCompositeTests` (flat
   pictures: overlay bit-identical, outline-only black; 8-pixel checkerboard mask = reference; threshold above the
   contrast: nothing; off bit-identical).
3. Scenes: `swift test --package-path Packages/SceneFormat --filter EdgeOutlineSceneEntryTests`; RenderGoldens
   `EdgeOutlineSceneGoldenTests`.
4. App (own simulator): `EdgeOutlineSettingTests`, `EdgeOutlineUITests`.
5. Device `{device}` (FX-014-T18): on D1, Camera visual, Edge outline on at threshold 0.2, widths 1 and 3, both modes:
   outlines follow edges, flat areas stay clean; note the frame rate with and without it.
