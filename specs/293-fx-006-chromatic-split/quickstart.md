# Quickstart: FX-006 Chromatic Split

1. `swift test --package-path Packages/Compositor --filter ChromaticSplit` — model and GPU acceptance (zero
   identity, bounds, shift, reference).
2. `swift test --package-path Packages/SceneFormat --filter SceneEffectChain` — scene round trip.
3. `swift test --package-path Packages/RenderGoldens` — goldens unchanged plus the split golden.
4. App (own simulator "FX6 iPhone 17"): `ChromaticSplitSettingTests`, `SettingsTests`, `LibraryBackupAppTests`,
   `EffectChainSettingTests`, UI `ChromaticSplitUITests`.
5. `{device}`: on D1 open Photo, turn on Chromatic split at 2%, check fringes and the frame rate.
