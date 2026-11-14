# Quickstart: OUT-004 Aspect Correction

## A. Mac (simulator, automated)

1. `swift test --package-path Packages/PresentationLifecycle --filter ExternalOutputPlacementTests`
2. App unit tests `ExternalOutputCorrectionTests` and UI test `ExternalDisplayUITests` on an iOS 27.2 simulator.

## B. Device `{device}`

1. Connect D1 to a 16:9 TV (HDMI adapter): Settings › External Display: Fit + Device → pillarbox with
   black bars; Fill → covered; Display → full screen. Circles in a test preset are round.
2. Connect through a composite/analog adapter (non-square pixels) if available: Pixel aspect
   Automatic keeps circles round; 1.0 shows the uncorrected ellipse.
3. Blackout: the whole screen, bars included, is black.
