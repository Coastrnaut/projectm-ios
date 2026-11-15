# Quickstart: CAM-011 validation

1. `swift test --package-path Packages/ParameterGraph --filter Motion` — the synthetic-stream acceptance
   (`MotionTrackerTests`): bounds, calibration to 0.5, seam crossing, shake envelope, ID round trip.
2. The whole ParameterGraph suite passes (under 1 minute).
3. App: build-for-testing on "CAM11 iPhone 17", then
   `test-without-building -only-testing:projectM-iOSTests/MotionModulationAppTests` (a motion binding drives the
   glow from an injected sampler; the sensor stops on background and on unbind) and
   `-only-testing:projectM-iOSTests/LibraryBackupAppTests`.
4. UI: `-only-testing:projectM-iOSUITests/MotionCalibrationUITests` — Settings › Motion with the stand-in shows a
   tilt, Calibrate brings "Tilt forward" to 50 %.
5. Repo checks from AGENT_RULES.md.
6. `{device}` on D1: bind a scene's glow to Tilt forward, Calibrate, tilt and shake; background the app and check
   the sensor stops (no motion-related battery entry).
