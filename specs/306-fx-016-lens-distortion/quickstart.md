# Quickstart: FX-016 Lens Distortion

1. Model (any OS): `swift test --package-path Packages/Compositor --filter LensDistortionModelTests` (zero strength maps
   every pixel to itself; at ±1, zoom on and off, every sample and tap in range and every value finite at 1:1, 16:9,
   9:16, 1:64, 64:1; radial mapping strictly increasing).
2. GPU acceptance (Mac): `swift test --package-path Packages/Compositor --filter LensDistortionCompositeTests` (off and
   strength 0 bit-identical; ±1 equals the reference, finite; corners black with zoom off).
3. Scenes: `swift test --package-path Packages/SceneFormat --filter LensDistortionSceneEntryTests`; RenderGoldens
   `LensDistortionSceneGoldenTests`.
4. App (own simulator): `LensDistortionSettingTests`, `LensDistortionUITests`.
5. Device `{device}` (FX-016-T17): on D1, Camera visual, Lens distortion on at +100 % and −100 %, zoom on and off: the
   picture bulges and pinches, corners show picture (or black with zoom off at barrel), no sparkles at the corners;
   note the frame rate with and without it.
