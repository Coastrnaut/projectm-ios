# Quickstart: OUT-014 Output Profile Export

## A — Mac (automated)
1. `swift test --package-path Packages/PresentationLifecycle --filter OutputProfileTests`
2. `xcodebuild build-for-testing` (scheme `projectM-iOS`, simulator "OUT14 iPhone 17"), then
   `test-without-building -only-testing:projectM-iOSTests/OutputProfileAppTests` and
   `-only-testing:projectM-iOSUITests/OutputProfileUITests`.

## B — D1 with a projector ({device}, OUT-014-T13)
1. Connect a projector over HDMI; set a corner pin and a colour calibration until the test card fits.
2. Settings › External Display › Export output profile…, save to Files.
3. Reset the corner pin and the calibration; Import output profile…, pick the file: no warning, the picture is pinned
   and calibrated as before. Connect a different display and import again: the warning names the difference.
