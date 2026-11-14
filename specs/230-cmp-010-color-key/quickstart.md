# Quickstart: CMP-010 Color Key

Run from the worktree root (owner rule 7 budgets).

1. CPU reference (also the Linux shape):
   `swift test --package-path Packages/Compositor --filter LayerColorKeyReferenceTests`
   and `swift build --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`.
2. GPU acceptance (green key): `swift test --package-path Packages/Compositor --filter LayerColorKeyCompositeTests`.
   Expected: green patch alpha ≤ 1/255; red, blue, white, skin and dark-green patches equal to the
   unkeyed draw within 1/255; feather ramp monotonic and equal to the reference; no extra pass.
3. Scenes: `swift test --package-path Packages/SceneFormat --filter SceneColorKeyTests`.
4. Goldens: `swift test --package-path Packages/RenderGoldens --filter ColorKeyGoldenTests` (host) and the
   same suite on the "CMP10 iPhone 17" simulator.
5. App: `LayerColorKeyEditTests` (unit) and `LayerInspectorUITests/testColorKeyToggleDragAndUndo` on the simulator.
6. Bench (opt-in, not device evidence): `CMP010_BENCH=1 swift test --package-path Packages/Compositor --filter LayerColorKeyCompositeTests/testBench`.
