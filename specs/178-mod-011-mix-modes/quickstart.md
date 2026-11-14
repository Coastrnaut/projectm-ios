# Quickstart: MOD-011

```bash
swift test --package-path Packages/ParameterGraph --filter ModulationMixOrderTests
swift test --package-path Packages/VisualGenerators --filter GlowModulationOrderTests
swift test --package-path Packages/SceneFormat --filter SceneModulationRestoreTests
```

App: `ModulationMixOrderAppTests` on the private simulator (two bindings on the glow intensity).
