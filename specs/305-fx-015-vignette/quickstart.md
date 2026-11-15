# Quickstart: FX-015 Vignette

1. Model (any OS): `swift test --package-path Packages/Compositor --filter VignetteModelTests`.
2. GPU acceptance (Mac): `swift test --package-path Packages/Compositor --filter VignetteCompositeTests` (off and
   intensity 0 bit-identical at centre and corners, centre exact at any intensity, monotonic falloff, centre control,
   reference match, finite).
3. Scenes: `swift test --package-path Packages/SceneFormat --filter Vignette`; RenderGoldens `VignetteSceneGoldenTests`.
4. App (own simulator): `VignetteSettingTests`, `VignetteUITests`.
5. Device `{device}` (FX-015-T15): on D1, Photo visual, Vignette at intensity 100 % and softness 10 % and 90 %, centre
   moved: edges darken smoothly, the middle is unchanged; note the frame rate with and without it.
