# Quickstart: CAM-010 Hand Pose Modulation

1. Package: `swift test --package-path Packages/ParameterGraph --filter HandFeatureTrackerTests` — normalisation,
   smoothing, recorded-pose determinism through the modulator.
2. Camera hook: `swift test --package-path Packages/Compositor --filter CameraPictureAnalyzer`.
3. App (simulator "CAM10 iPhone 17"): `-only-testing:projectM-iOSTests/HandTrackingAppTests` and
   `FaceTrackingAppTests` — consent gate, recorded poses through the analyzer and the Camera visual's modulation,
   nothing written or exported.
4. UI: `-only-testing:projectM-iOSUITests/HandTrackingConsentUITests` — sheet before activation, Cancel leaves it off.
5. Device `{device}` (D1): Camera visual, front camera, Hand tracking on; bind Pinch to the inner radius (DEBUG seed
   `-uitestBindCameraRadiusToPinch`); pinch and watch the ring; check the badge and iOS's indicator; note the frame rate.
