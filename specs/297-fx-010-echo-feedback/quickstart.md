# Quickstart: FX-010 Echo Feedback

1. `swift test --package-path Packages/Compositor --filter Echo` — model, cap, schedule, GPU acceptance (off/0
   identity, cap 4, moving dot vs reference, 600-frame memory soak).
2. `swift test --package-path Packages/SceneFormat --filter SceneEffectChain` — scene round trip.
3. `swift test --package-path Packages/RenderGoldens --filter EffectChainScene` — inactive exact, save/reload.
4. App (own simulator "FX10 iPhone 17"): `EchoSettingTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests`,
   `EffectChainSettingTests`, `SettingsTests`, UI `EchoUITests`.
5. `{device}`: on D1 open Camera, turn on Echo with 4 echoes, wave a hand: 4 fading copies; the frame rate holds.
