# Quickstart: SHOW-014 Emergency Blackout

## Host and simulator (the Mac)

```bash
swift test --package-path Packages/PresentationLifecycle --filter OutputBlackoutTests
xcodegen generate
xcrun simctl create "SHOW14 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath .autonomous/derived-data-show-014 \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/EmergencyBlackoutUITests \
  -only-testing:projectM-iOSUITests/OutputBlackoutUITests -only-testing:projectM-iOSUITests/ExternalDisplayUITests \
  -only-testing:projectM-iOSUITests/NativeVisualUITests > xcodebuild.log 2>&1
```

Expected: every test passes; `EmergencyBlackoutUITests` under 30 s each. Simulator results are
never device evidence.

## Device (owner's hands, SHOW-014-T12 `{device}`)

1. D1 with an HDMI adapter (or AirPlay) and D2 with a hardware keyboard and an external display.
2. Start In-App Playback, let the controls hide.
3. Tap the corner button once: the external display is black at once; the music plays on.
4. Tap Restore in the top badge: the same preset fades back in.
5. On D2 press B (black), B again (restore). Repeat with no display: the device's picture goes black.
