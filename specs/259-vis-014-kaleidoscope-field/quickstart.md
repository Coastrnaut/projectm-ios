# Quickstart: VIS-014 Kaleidoscope Field

```bash
swift test --package-path Packages/VisualGenerators --filter 'Kaleidoscope|NoiseField'
swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter 'Kaleidoscope|NoiseField'
swift test --package-path Packages/RenderGoldens --filter 'Kaleidoscope|NoiseField'
```

App: Settings → Visual → Kaleidoscope; Wedges stepper. Device (`{device}`): D1 with music, the PERF-001/007 overlay
holds the display's frame rate and no seam is visible.
