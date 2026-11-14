# Quickstart: FX-009 Motion Feedback

1. Reference (Linux shape): `swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL
   -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter MotionFeedbackModelTests`.
2. GPU acceptance: `swift test --package-path Packages/Compositor --filter 'MotionFeedback|RenderCache|SceneTransitionBus|CompositeFlashGuard|TexturePool'`
   — red then blue: the first frame after each reset trigger is bit-identical to Trails off; decay at 60/120 fps;
   off identity; no composite reuse while on; Strict cap; the guard engages on a strobe with trails; pool checkouts
   back to the start.
3. Catalog: `swift test --package-path Packages/Compositor --filter ColorGradeCatalogTests`.
4. Regressions: RenderGoldens and LibraryBackup package tests.
5. App: on an own simulator, `-only-testing:projectM-iOSTests` (MotionFeedbackSettingTests and the backup/erase key
   tests) and `-only-testing:projectM-iOSUITests/TrailsUITests`.
6. Device (`{device}`): on D1, Camera or Photo visual, Settings → Trails on, Length 0.50 s: moving bars leave trails;
   step a show cue: no ghost of the previous scene; frame rate in the performance overlay recorded with and
   without Trails.
