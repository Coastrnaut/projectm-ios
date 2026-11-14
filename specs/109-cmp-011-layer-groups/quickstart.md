# Quickstart: CMP-011 Layer Groups

Run from the repository root on the Mac (Xcode 27.2). Logs go to `.autonomous/logs/cmp-011/`.

```bash
swift test --package-path Packages/Compositor --filter 'LayerGroup'          # model + GPU read-back
swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL \
  -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter LayerGroupStackTests   # Linux shape
swift test --package-path Packages/SceneFormat --filter 'SceneGroup|SceneMigrationMatrix'
CMP011_BENCH=1 swift test -c release --package-path Packages/Compositor --filter testBenchGroup   # GPU time, not device evidence
```

Expected: every test passes; the bench prints flattened vs isolated GPU time for a 4-layer group at
1920 × 1080. Regression: SceneFormat, RenderGoldens, ImportFuzz, ShowControl, SceneArchive full
suites and the app unit tests (`-only-testing:projectM-iOSTests`) on a dedicated iOS 27.2
simulator.
