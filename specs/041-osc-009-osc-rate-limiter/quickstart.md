# Quickstart: OSC-009 OSC Rate Limiter

## A — Package (host, also Linux CI)

```bash
swift test --package-path Packages/PerformanceControl --filter 'OSCRateLimiter|OSCFlood|OSCRefreshGate|OSCDispatcher|OSCReceiver'
swift test --package-path Packages/PerformanceControl     # whole suite, < 1 min
```

Expected: limiter tests (burst, refill, isolation, global cap, eviction, coalescing), the flood fixture
(OSC-009-S1 to S3) and the loopback integration test (S5) pass.

## B — App (iOS 27.2 simulator, unsigned)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath .autonomous/derived-data-osc-009 \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/OSCReceiverUITests \
  -only-testing:projectM-iOSUITests/OSCNetworkAccessUITests -only-testing:projectM-iOSUITests/OSCRateLimiterUITests
```

Expected: `OSCReceiverCoordinatorTests.testFloodCoalescesMainActorRefreshes` (OSC-009-S4) and the
Settings row UI test pass. Simulator results are never device evidence.

## C — Device LAN (`{device}`, last stage)

On D1 with OSC on, a LAN controller floods `/projectm/test` (for example a script at 2,000 msg/s for
10 s): the visualizer keeps rendering, Settings shows a growing "Rate-limited N", and the test value
ends at the last value sent.
