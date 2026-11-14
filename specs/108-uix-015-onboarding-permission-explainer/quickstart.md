# Quickstart: UIX-015 validation

Prerequisites: `xcodegen generate`; preset submodules initialised; own simulator
(`xcrun simctl create "UIX15 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2`).

1. Unit: `xcodebuild test … -only-testing:projectM-iOSTests/PermissionExplainerTests
   -only-testing:projectM-iOSTests/PermissionCatalogTests` — policy table C2, coordinator transitions,
   catalog fallbacks.
2. UI: `-only-testing:projectM-iOSUITests/PermissionExplainerUITests` — camera (stand-in
   `notDeterminedDeny`), local network (`-uitestOSCFailure localNetworkDenied`), microphone Not now
   (simulator microphone never asked: `simctl privacy <udid> reset microphone org.projectmios.ProjectMiOS`).
3. Microphone real denial: `simctl privacy <udid> revoke microphone …` and
   `TEST_RUNNER_FILE013_MIC_REVOKED=1`, run `PermissionAuditUITests/testMicrophoneDeniedForRealShowsBannerAndOpensSettings`
   (no explainer after denial, Choose source offered).
4. Regression: CameraUITests, PermissionAuditUITests, OSCReceiverUITests.
5. Device `{device}` (D1): real camera and local network prompts follow the explainer; deny each,
   use the feature again, no explainer.
