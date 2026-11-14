# Quickstart: FX-020 Effect Chain Presets

Run from the worktree root.

1. Compositor tests (host GPU, under 1 minute):
   `swift test --package-path Packages/Compositor --filter "OutputEffectOrderTests|EffectOrderCompositeTests|MotionFeedbackCompositeTests|ColorGradeOutputTests"`
   — default order bit-identical to no order set; Color→Trails differs from Trails→Color with Trails and a
   non-neutral grade; single-effect orders identical.
2. Scene tests: `swift test --package-path Packages/SceneFormat --filter "SceneEffectChain|SceneMigrationMatrix"`
   — the acceptance (`SceneEffectChainRenderTests`): reorder, write the file, read it back, render; equals
   Color→Trails rendered directly, differs from Trails→Color. QA-004 meta-test passes.
3. App unit tests on the private "FX20" simulator: `-only-testing:projectM-iOSTests/EffectChainSettingTests`.
4. UI test (under 30 s): `-only-testing:projectM-iOSUITests/EffectChainUITests` — Settings › Effect order,
   move Color above Trails, the Settings row reads "Color → Trails".
5. Repository checks: compliance, docs, motion policy, permission catalog, status events, script tests,
   privacy manifest, network symbols.
6. `{device}`: on D1 with a photo, Trails on and a strong Color grade, compare the two orders by eye and
   confirm the flash guard still limits a strobing fixture in both orders.
