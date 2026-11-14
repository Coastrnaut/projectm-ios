# Quickstart: AUD-012 Source Crossfade

## Package tests (host)

```bash
swift test --package-path Packages/AudioCore --filter SourceHandoffTests
swift test --package-path Packages/AudioCore -Xswiftc -DAUDIOCORE_NO_AVFAUDIO   # Linux shape
swift test --package-path Packages/CaptureKit --filter SourceSwitchTests
```

Expected: no non-finite or out-of-range sample in either ring; the label sequence A → switching →
B; the handoff within 300 ms of sample clock; the ramp step bound; bit-identical clean audio.

## App (simulator "AUD12 iPhone 17", iOS 27.2)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,name=AUD12 iPhone 17' \
  -derivedDataPath .autonomous/derived-data-aud-012 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/SourceSwitchUITests \
  -only-testing:projectM-iOSUITests/StatusUITests -only-testing:projectM-iOSUITests/TransportUITests \
  -only-testing:projectM-iOSUITests/InterruptionUITests
```

Manual (Debug): `-uitestResetNotice -uitestFake inAppPlayback,systemAppCapture -uitestFakeLevel loud
-autostart inAppPlayback`, tap the picture, "Switch Source", "System/App Capture": the indicator
reads "Switching source…" briefly, then "System/App Capture · Active audio"; the visual keeps moving.

## Device (`{device}`, last phase)

Switch between Microphone, In-App Playback and System/App Capture on D1/D2 (D3: no System/App
Capture) with a route change and an interruption during a switch; record the indicator sequence and
that projectM never freezes on old audio.
