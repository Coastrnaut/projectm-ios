# Quickstart: PERF-010 validation

## Mac (simulator, iOS 27.2)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath <dd> CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests/SessionRecoveryTests \
  -only-testing:projectM-iOSUITests/SessionRecoveryUITests
```

Expected: unit tests pass (marker state machine, crash loop, launch policy: OSC never started, offer,
Start fresh defaults); UI tests: after `terminate()` without a background transition the offer
appears, no OSC badge, the probe says `osc=off`, no camera badge or frames; Reopen restores Circular
Spectrum with 16 bars and OSC stays off. After Home then terminate, no offer.

## Device (`{device}`, D1)

1. DEBUG build with `-uitestDiagnostics` off; turn OSC on in Settings and choose Camera.
2. Launch the app from the home screen (not from Xcode, so no debugger catches the crash), then
   Settings › "Crash now (DEBUG)" at the bottom (calls `fatalError`).
3. Relaunch from the home screen: the card is shown, the OSC badge and the green camera dot are
   absent; Settings shows OSC off. Reopen: the scene returns; still no camera or OSC.
