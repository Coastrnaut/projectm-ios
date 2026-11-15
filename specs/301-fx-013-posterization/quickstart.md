# Quickstart: FX-013 Posterization

## Mac (packages)

```bash
swift test --package-path Packages/Compositor --filter 'Posterize|ColorGradeOutputTests|ColorGradeCatalogTests|ContrastCurve'
swift test --package-path Packages/SceneFormat --filter SceneEffectChainTests
```

Expected: level counts ≤ L for L ∈ {2, 3, 6, 16, 32} (CPU and GPU), off bit-identical, extremes bounded, dither
deterministic, block 96 bytes, scene round-trip.

## App (simulator "FX13 iPhone 17", iOS 27.2)

`xcodegen generate`, `build-for-testing`, then `test-without-building` with
`-only-testing:projectM-iOSTests/ColorGradeSettingTests -only-testing:projectM-iOSTests/LibraryBackupAppTests
-only-testing:projectM-iOSTests/SettingsTests -only-testing:projectM-iOSUITests/ColorGradeUITests`.

Manual: Settings → Color → Posterize on; the Camera or Photo visual shows flat bands; Levels 2 gives black/white
per channel; Dither on breaks bands into a fixed fine pattern.

## Device `{device}` (FX-013-T14)

On D1, with a compositor-backed visual, Posterize on at 6 levels with Dither on: frame rate within 1 fps of off.
