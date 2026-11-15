# Quickstart: OUT-003 Independent Output Resolution

## A — Host and simulator (Mac)

1. `swift test --package-path Packages/PresentationLifecycle --filter ExternalOutputResolutionTests` — the arithmetic (OUT-003-S1).
2. App unit tests on the iOS 27.2 simulator: `-only-testing:projectM-iOSTests/ExternalOutputResolutionAppTests` — a real Text visual on an external slot changes drawable and snapshot pixel size while scene-space values stay equal (OUT-003-S2); clamping, hold deferral, device return, persistence.
3. UI test: `-only-testing:projectM-iOSUITests/ExternalDisplayUITests/testTheResolutionSettingChangesTheExternalDrawable` — the fake 1920 × 1080 display, 720p → probe `drawable=1280x720` (OUT-003-S3).
4. Regression: `ExternalOutputCorrectionTests`, `ExternalDisplayCoordinatorTests`, `HotPlugAcceptanceTests`, `OutputBlackoutCoordinatorTests`, `ExternalRehearsalTests` (OUT-003-S4).

Simulator results are never device evidence.

## B — Device with a real external display (`{device}`, OUT-003-T10)

1. Connect D1 to a 4K television (USB-C to HDMI) and start any visual.
2. Settings › External Display › Resolution: Native, then 1080p, then 720p, then Custom 50 %.
3. Expected: the picture's composition (layers, text, crops) is identical at every choice; only sharpness changes; on D1 (6 GB) Native is reported clamped only if the budget is exceeded; the log line `external resolution: …` shows the drawable size.
