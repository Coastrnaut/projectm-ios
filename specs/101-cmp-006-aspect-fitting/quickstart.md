# Quickstart: validating CMP-006

All from the worktree root on the Mac Studio. Budgets: owner rule 7.

1. Geometry on the host and in the Linux shape:
   - `swift test --package-path Packages/Compositor --filter "LayerFitGeometryTests|ImageGeometryTests|VideoPictureGeometryTests"`
   - `swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter LayerFitGeometryTests`
   - Expect: the 2 × 2 × 4 table passes, anchors kept across orientations.
2. GPU read-back: `swift test --package-path Packages/Compositor --filter LayerFitCompositeTests`.
   Expect markers found where the geometry predicts, portrait then landscape, per mode; one blend
   mode case, one transform case; GPU timings printed (not device evidence).
3. Scene format: `swift test --package-path Packages/SceneFormat`. Expect round trip of each mode
   and anchor, unknown mode kept and warned, scenes without `fit` byte-identical.
4. Regression: `swift test` for Compositor, SceneFormat, RenderGoldens, ImportFuzz, ShowControl,
   SceneArchive; app unit tests on a dedicated iOS 27.2 simulator (`-only-testing:projectM-iOSTests`).
5. Docs and rules: `python3 scripts/check_compliance.py`, `validate_docs.py`,
   `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`.
