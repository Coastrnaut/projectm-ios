# Quickstart: CMP-012 Solo and Mute checks

Run on the Mac from the repository root (or the feature worktree).

1. CPU rule, host: `swift test --package-path Packages/Compositor --filter LayerSoloMuteTests`
   → all pass in well under a second.
2. CPU rule, Linux shape: `swift test --package-path Packages/Compositor --filter LayerSoloMuteTests
   -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`.
3. GPU read-back: `swift test --package-path Packages/Compositor --filter LayerSoloMuteCompositeTests`
   → solo (only the soloed layer drawn, stack unchanged), mute, multi-solo, solo plus mute, three group cases, bit-identical restore,
   0 preparations and 0 allocations caused by the overlay.
4. The acceptance with documents: `swift test --package-path Packages/SceneFormat --filter SceneSoloMuteTests`
   → only the soloed layer drawn by the real compositor, scene bytes and saved flags identical before,
   during and after, no undo step.
5. GPU time (opt-in, Mac only, not device evidence; `-DDEBUG` because other tests in the target use DEBUG-only hooks):
   `CMP012_BENCH=1 swift test -c release -Xswiftc -DDEBUG --package-path Packages/Compositor --filter LayerSoloMuteCompositeTests/testBench`.
6. Regression: full Compositor and SceneFormat suites, RenderGoldens, ImportFuzz, ShowControl,
   SceneArchive, app unit tests on an own iOS 27.2 simulator.

Results go to `docs/test-reports/solo-and-mute.md`.
