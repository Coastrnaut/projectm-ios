# Quickstart: UIX-012 Touch Color Sampler

1. Package: `swift test --package-path Packages/Compositor --filter 'PreviewPixelMappingTests|ColorSampleCompositorTests'` — mapping cases and the GPU pattern acceptance pass.
2. App unit: `xcodebuild test-without-building … -only-testing:projectM-iOSTests/ColorSamplerTests` — sample write, undo, refusals, rejection, timeout.
3. UI: `-only-testing:projectM-iOSUITests/ColorSamplerUITests` — Text visual, eyedropper, tap, the eyedropper reads the fixture colour.
4. Device (D1): show a spectrum with the Text visual, sample a bar, compare the text colour by eye; with VoiceOver, hear the announcement and use the escape gesture to cancel.
