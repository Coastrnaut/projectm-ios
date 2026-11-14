# Quickstart: validating CMP-007 Shape Masks

Prerequisites: the Mac Studio (Xcode 27.2), the worktree checked out, `Vendor/presets/*`
submodules initialised for the app tests.

1. CPU reference (host and Linux shape):
   ```bash
   swift test --package-path Packages/Compositor --filter LayerMaskReferenceTests
   swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL \
     -Xswiftc -DANALYSIS_NO_ACCELERATE --filter LayerMaskReferenceTests
   ```
   Expected: all pass in well under a second.
2. GPU read-back: `swift test --package-path Packages/Compositor --filter LayerMaskCompositeTests`.
   Expected: per shape 0 outside violations, inside equal, edge error ≤ 0.01 (printed table).
3. GPU time (opt-in, Release): `CMP007_BENCH=1 swift test -c release --package-path Packages/Compositor
   --filter LayerMaskCompositeTests/testBench`. Recorded in `docs/test-reports/shape-masks.md`, not
   device evidence.
4. Scenes: `swift test --package-path Packages/SceneFormat` (includes `SceneMaskTests` and the
   QA-004 meta-test). Expected: all pass.
5. Regression: RenderGoldens, ImportFuzz, ShowControl, SceneArchive packages; app unit tests on a
   dedicated "CMP7 iPhone 17" iOS 27.2 simulator (`-only-testing:projectM-iOSTests`), deleted after.
6. Checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
   `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`.
