# Quickstart: CMP-013 Render Caching checks

Run from the repository root (Mac host; GPU tests skip without a Metal device).

```bash
swift test --package-path Packages/Compositor --filter 'RenderCache|TextLayerCache'   # model + GPU, < 30 s
swift test --package-path Packages/Compositor                                          # whole suite
swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL \
  -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter RenderCacheModel   # Linux shape
CMP013_BENCH=1 swift test --package-path Packages/Compositor --filter RenderCacheBench      # GPU time, recorded
```

Expected: the acceptance test reports 1 photo render over 10 frames and exactly one more after a fit
change; every invalidation test passes; the bit-identity test compares every output frame of the
scripted sequence byte for byte with zero differences; dynamic layers render 10 of 10.

Regression: RenderGoldens (goldens unchanged), SceneFormat, ImportFuzz, ShowControl, SceneArchive,
VisualGenerators, app unit tests and the photo and text UI tests on an own iOS 27.2 simulator.
