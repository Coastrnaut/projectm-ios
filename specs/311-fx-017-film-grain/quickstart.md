# Quickstart: FX-017 Film grain

1. Model (any OS): `swift test --package-path Packages/Compositor --filter FilmGrainModelTests` (hash vectors, exact
   noise, cells, grain-frame rule, zero mean, bound, opacity 0 identity).
2. GPU acceptance (Mac): `swift test --package-path Packages/Compositor --filter FilmGrainCompositeTests` (off and
   opacity 0 bit-identical; GPU hash = CPU; output = reference within a half-float step; fixed seed stable; seeds and
   temporal steps differ; mean ≈ 0; finite).
3. Scenes: `swift test --package-path Packages/SceneFormat --filter FilmGrainSceneEntryTests`; RenderGoldens
   `FilmGrainSceneGoldenTests` (record with `GOLDEN_RECORD=1` on the host and `TEST_RUNNER_GOLDEN_RECORD=1` on the
   simulator).
4. App (own simulator): `FilmGrainSettingTests`, `FilmGrainUITests`.
5. Device `{device}` (FX-017-T17): on D1, Photo visual, Film grain on at 100 %, sizes 1-3, colour and monochrome, Vary
   over time on (grain moves gently, no strobing) and with Reduce Motion on (grain still); note the frame rate with and
   without it.
