# Quickstart: FX-005 Contrast Curves

1. Reference (host, Linux shape): `swift test --package-path Packages/Compositor --filter ContrastCurveReferenceTests`
   — identity sweep, monotone, endpoints, bounds, extremes.
2. GPU (host): `swift test --package-path Packages/Compositor --filter "ContrastCurveOutputTests|ColorGradeOutputTests"`.
3. Scene: `swift test --package-path Packages/SceneFormat --filter EffectChain`.
4. App (own simulator "FX5 iPhone 17"): `ColorGradeSettingTests`, `LibraryBackupAppTests`, `SettingsTests`,
   `ColorGradeUITests`.
5. Device (`{device}`): Photo visual, Settings → Color → Contrast S-curve and Filmic at 100%; frame rate unchanged
   within noise (FX-005-S7).
