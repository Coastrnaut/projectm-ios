# Quickstart: FX-007 Directional Blur

1. `swift test --package-path Packages/Compositor --filter DirectionalBlur` — model and GPU acceptance (zero identity,
   horizontal/vertical spread with energy kept, bounds, reference, tap count).
2. `swift test --package-path Packages/SceneFormat --filter SceneEffectChain` — scene round trip.
3. `swift test --package-path Packages/RenderGoldens --filter EffectChainScene` — zero blur exact, save/reload.
4. App (own simulator "FX7 iPhone 17"): `DirectionalBlurSettingTests`, `LibraryBackupAppTests`,
   `LibraryEraseAppTests`, `EffectChainSettingTests`, `SettingsTests`, UI `DirectionalBlurUITests`.
5. `{device}`: on D1 open Photo, turn on Directional blur at 2%, check the streak and the frame rate.
