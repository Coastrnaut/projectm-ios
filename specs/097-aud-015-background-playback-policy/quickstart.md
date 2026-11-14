# Quickstart: AUD-015 Background Playback Policy

## Mac (host and simulator)

```bash
swift test --package-path Packages/CaptureKit --filter "BackgroundPolicyTests|CaptureManagerTests"
xcodegen generate
# app unit tests and the UI test on a private iOS 27.2 simulator
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=<udid>" \
  -only-testing:projectM-iOSTests/BackgroundPolicyAppTests \
  -only-testing:projectM-iOSTests/LifecycleCoordinatorTests \
  -only-testing:projectM-iOSUITests/BackgroundPolicyUITests \
  -derivedDataPath .autonomous/derived-data-aud-015 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180
python3 scripts/check_compliance.py && python3 scripts/check_permission_catalog.py
```

Expected: every policy case passes; the UI test sees "In-App Playback · Active audio" and the
notice "Playback paused while projectM-iOS was in the background." after Home and return.

## Device (AUD-015-T13, D1, per source)

For Microphone, In-App Playback and System/App Capture: start the source, then (a) press Home and
return after 10 s, (b) lock and unlock into the app, (c) lock, unlock onto the Home Screen, wait
10 s, then open the app. Expected: per the contract's table; the microphone indicator is off
while away in (a)-(c); System/App Capture ends on lock with "Ended by system". Record the export
for each run.
