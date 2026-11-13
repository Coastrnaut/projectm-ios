# Quickstart: OUT-010 Output Blackout Isolation

Simulator and host results are never device evidence (Constitution X).

## A. Host and Linux: the rules

```bash
swift test --package-path Packages/PresentationLifecycle --filter OutputBlackoutTests
```

Expect: one-frame blackout with a fake frame clock, the fade's rise rate, the restore spacing and
fastest toggling within the flash budgets (FlashAnalysis on a white picture).

## B. Simulator: app unit and UI tests

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath <dd> CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests/OutputBlackoutCoordinatorTests \
  -only-testing:projectM-iOSUITests/OutputBlackoutUITests
```

Expect: the cover opaque inside the call; black after connect, disconnect, visual change and
re-entry; the UI test (fake external display): Black out → `outputBlackout` = `black`, Settings
opens and closes, Restore → `live`, `visualRunning` = `yes`, `sourceStarts` = 1.

## C. Simulator: the real external screen (headless, not a unit test)

1. Boot the simulator and install the Debug app.
2. `xcrun simctl io <udid> screenConfig --display external power on`
3. Launch with `-autostart inAppPlayback -uitestStartBlackedOut` (DEBUG only: the coordinator
   starts blacked out, as if Black out had been tapped).
4. After 5 s, `xcrun simctl io <udid> screenshot --display external black.png`: every pixel black.
5. Relaunch with `-autostart inAppPlayback` (live), after 5 s screenshot again: the visualization.
6. `xcrun simctl io <udid> screenConfig --display external power off`

## D. Physical displays (`{device}`, owner)

On D1 and D2 with a USB-C/HDMI adapter and with AirPlay to an Apple TV: start a visualization,
connect, tap Black out: the display is black at once; the device's controls still work; Restore
fades in over about 1 s (4 s with Reduce flashing on). Optional: film the display and the device
with a 240 fps camera and count frames from the tap's touch-down to black (expect at most the
display's frame plus its own latency). Unplug while blacked out: the device stays black.
