# Quickstart: FX-011 Pixel Sorting Approximation

1. Model (any OS): `swift test --package-path Packages/Compositor --filter PixelSortModelTests` (budget plan over sizes
   and spans; reference sorts segments and leaves others; threshold changes the output).
2. GPU acceptance (Mac): `swift test --package-path Packages/Compositor --filter PixelSortCompositeTests` (GPU equals
   the reference at two thresholds and both directions; off identical; one dispatch per active frame; budget skip).
3. Scenes: `swift test --package-path Packages/SceneFormat --filter PixelSortSceneEntryTests`; RenderGoldens
   `PixelSortSceneGoldenTests`.
4. App (own simulator): `PixelSortSettingTests`, `PixelSortUITests`.
5. Device `{device}` (FX-011-T16): on D1 and an external 4K display if available, Video visual, Pixel sort on at span
   32 and 64, both directions: note the GPU frame time with and without it (Xcode GPU report or the app's frame meter).
