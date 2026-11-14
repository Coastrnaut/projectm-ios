# Quickstart: CMP-009 Luma Key

Run from the worktree root (owner rule 7 budgets).

1. CPU reference (also the Linux shape):
   `swift test --package-path Packages/Compositor --filter LayerLumaKeyReferenceTests`
   and `swift build --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`.
2. GPU acceptance (black key): `swift test --package-path Packages/Compositor --filter LayerLumaKeyCompositeTests`.
   Expected: dark region alpha ≤ 1/255; bright patch equal to the unkeyed draw within 1/255; no extra pass.
3. Scenes: `swift test --package-path Packages/SceneFormat --filter SceneLumaKeyTests`.
4. Goldens: `swift test --package-path Packages/RenderGoldens --filter LumaKeyGoldenTests` (host) and the
   same suite on the "CMP9 iPhone 17" simulator.
5. App: `LayerLumaKeyEditTests` (unit) and `LayerInspectorUITests/testLumaKeyToggleDragAndUndo` on the simulator.
6. Bench (opt-in, not device evidence): `CMP009_BENCH=1 swift test --package-path Packages/Compositor --filter LayerLumaKeyCompositeTests/testBench`.
