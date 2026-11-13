# Quickstart: SCN-012 Scene Validation

1. Package (host and Linux shape):
   `swift test --package-path Packages/SceneFormat --filter 'SceneRepair|SceneSourceSafety'`
   and the same with `-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc
   -DANALYSIS_NO_ACCELERATE`. Expect the fixture table, idempotency and fuzz tests to pass in seconds.
2. App: `xcodegen generate`, then `xcodebuild test` on an own iOS 27.2 simulator with
   `-only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/SceneRepairUITests
   -only-testing:projectM-iOSUITests/ShowCueUITests -only-testing:projectM-iOSUITests/SessionRecoveryUITests`.
3. By hand (DEBUG): launch with `-uitestShowRepairSeed`, show the controls, Next: the report lists
   Missing media and Invalid mappings; Open with repairs shows a circular spectrum. Next again:
   "Cannot open" (newer version), Close.
