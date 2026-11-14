# Quickstart: UIX-011

1. `swift test --package-path Packages/SceneFormat --filter ScenePalettesTests` and `--package-path Packages/VisualGenerators --filter CustomPaletteTests`, `--package-path Packages/LibraryBackup --filter PaletteBackupTests`.
2. App: `-only-testing:projectM-iOSTests/PaletteAppTests` (acceptance: two linked layers update on a swatch edit; a new store reading the file resolves the same colours) and `projectM-iOSUITests/PalettePickerUITests`.
3. By hand: Settings › Palettes › New Palette, change a swatch, choose it for the scene; the native visual redraws; quit and reopen: the palette and the choice are kept.
