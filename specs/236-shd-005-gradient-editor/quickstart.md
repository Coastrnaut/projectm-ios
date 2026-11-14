# Quickstart: SHD-005 Gradient Editor

1. `swift test --package-path Packages/VisualGenerators --filter GradientRampTests` — CPU reference.
2. `swift test --package-path Packages/SceneFormat --filter PaletteGradientStopsTests` — model and file.
3. `swift test --package-path Packages/Compositor --filter MaterialGradientRampTests` — GPU samples at every stop equal the stored colour and alpha within 1/255 (all three modes), CPU vs GPU between stops, golden.
4. App: Settings › Palette › New Palette › move Stop 2's Position, lower an Alpha, pick Step; the strip and the visual follow (`PaletteGradientEditorUITests`).
