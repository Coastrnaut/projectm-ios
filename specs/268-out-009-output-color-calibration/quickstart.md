# Quickstart: OUT-009

1. Package: `swift test --package-path Packages/Compositor --filter DisplayCalibration` (pure + Metal pixels).
2. ANGLE (simulator): `DisplayCalibrationGLTests` in the ANGLERendering scheme.
3. App (simulator "OUT9 iPhone 17"): `DisplayCalibrationAppTests`, `DisplayCalibrationUITests`, plus
   `LibraryBackupAppTests`, `SettingsTests`.
4. `{device}` (OUT-009-T14): with a real display or projector connected to D1, set gamma 1.5 and red 0.8 on
   projectM and on a Photo visual; the display changes, the device does not; a recording made meanwhile is
   uncalibrated; a native spectrum is unchanged on the display (as the editor says).
