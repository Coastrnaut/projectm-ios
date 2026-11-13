# Quickstart: OSC-001 OSC Receiver checks

All commands run from the repository root (or the feature worktree).

## A. Package tests (macOS host; Linux in CI)

```bash
swift test --package-path Packages/PerformanceControl
```

Expect: decoder cases, fixed-seed fuzz (< 1 s), scope, dispatcher, receiver lifecycle, and on macOS
the loopback integration test (`OSCLoopbackIntegrationTests`): a float to `/projectm/test` changes
the test value; after stop a second packet changes nothing and the port binds again. The whole suite
stays under a minute.

## B. Compliance and shipping symbols

```bash
python3 scripts/check_compliance.py
swift build -c release --package-path Packages/PerformanceControl
nm -m Packages/PerformanceControl/.build/release/PerformanceControl.build/*.o | grep -c OSCLoopbackSender   # expect 0
```

## C. App (simulator)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,name=OSC iPhone 17' \
  -derivedDataPath .autonomous/derived-data-osc-001 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests/OSCReceiverCoordinatorTests -only-testing:projectM-iOSTests/SettingsTests \
  -only-testing:projectM-iOSUITests/OSCReceiverUITests
```

Expect: settings default off/9000; coordinator listens only while enabled and active; UI test (< 30 s):
toggle off by default, on → "Listening on port N", port 80 refused, off → "Off".

## D. Device LAN (last stage, owner) `{device}`

1. Install a Debug build on D1, open Settings, turn on "OSC receiver" (port 9000); allow Local Network.
2. From a computer on the same Wi-Fi, send `/projectm/test ,f 0.42` to the device's IP, port 9000
   (any OSC sender, e.g. `oscsend <ip> 9000 /projectm/test f 0.42`).
3. Expect "Test value 0.42". Turn OSC off; send 0.9; the value stays 0.42.
4. Record device, iOS build and result in `docs/test-reports/osc-receiver.md`.
