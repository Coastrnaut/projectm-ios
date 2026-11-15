# Quickstart: VIS-013 Noise Field

```bash
swift test --package-path Packages/VisualGenerators --filter 'NoiseField|SeededNoise'
swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter 'NoiseField|SeededNoise'
swift test --package-path Packages/Compositor --filter 'MaterialNoise|NoiseTextureReference|SharedNoiseSource'
swift test --package-path Packages/RenderGoldens --filter NoiseField
```

App: Settings → Visual → Noise Field; Frequency, Octaves, New Seed. Device (`{device}`): D1 with music, the
PERF-001/007 overlay holds the display's frame rate.
