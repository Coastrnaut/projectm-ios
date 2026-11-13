# Quickstart: validating OUT-001

Simulator results are never device evidence (Constitution X). Never use the Simulator panel tool
(owner rule 8).

## A. Automated (Mac)

```bash
swift test --package-path Packages/PresentationLifecycle            # routing rules (also Linux)
swift test --package-path Packages/Compositor --filter ExternalOutputSizeTests
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath .autonomous/derived-data-out-001 \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests/ExternalDisplayCoordinatorTests \
  -only-testing:projectM-iOSUITests/ExternalDisplayUITests
```

The ANGLE resize test runs with the ANGLERendering package tests on the simulator
(`FlashLimiterTests/testStrobeHistorySurvivesAnExternalResize`).

Expected: every test passes. The UI test shows the note on the device while the fake display is
connected, shows the visual again after a disconnect, and reports `sourceStarts` 1 throughout.

## B. Simulator external display, headless (scripted hot-plug)

```bash
APP=.autonomous/derived-data-out-001/Build/Products/Debug-iphonesimulator/projectM-iOS.app
xcrun simctl install $UDID $APP
xcrun simctl launch $UDID org.projectmios.ProjectMiOS -uitestDiagnostics -autostart inAppPlayback -uitestUnlocked NO
xcrun simctl io $UDID screenConfig --display external power on       # connect TVOut (720 × 480 @1)
xcrun simctl io $UDID screenshot --display external ext.png           # the visualization alone
xcrun simctl io $UDID screenshot --display internal dev.png           # controls / note, no visual
xcrun simctl io $UDID screenConfig --display external power off      # disconnect
xcrun simctl io $UDID screenshot --display internal dev-after.png     # the visualization back on the device
```

Run it on iOS 27.2 (the scene accessory) and on iOS 26.5 (the Info.plist role). The coordinator's
log shows each step: `xcrun simctl spawn $UDID log show --last 1m --info --predicate 'category == "ExternalDisplay"'`.

Expected: `ext.png` is a non-black visualization filling 720 × 480. `dev.png` is black except the
note and any controls. `dev-after.png` shows the visualization. The app keeps running throughout.

## C. Physical displays (owner's hands, last)

On D1, D2 and D3, with a USB-C/HDMI adapter and with AirPlay to an Apple TV (choose a display
rather than mirroring), and on D2 with Stage Manager on an extended display:

1. Start In-App Playback and the projectM visual. Connect the display: the TV shows the
   visualization alone and the device shows the controls and the note.
2. Switch to Circular Spectrum, then Camera: each shows on the TV, and the camera badge stays on the
   device.
3. Unplug and replug the display during playback: the music never stops and the visualization moves
   back and forth.
4. Change the TV's resolution or refresh rate (Apple TV: Settings › Video and Audio): no crash.
   Note the fps in the performance overlay at 60 Hz and at 50 Hz or 24 Hz (OUT-013 input).
