# Quickstart: OSC-007 OSC Network Access Switch

Simulator and host results are never device evidence.

## A. Unit and real-transport tests (simulator)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,id=<private iOS 27.2 simulator>' \
  -derivedDataPath .autonomous/derived-data-osc-007 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests/OSCNetworkAccessTests \
  -only-testing:projectM-iOSTests/OSCReceiverCoordinatorTests > osc007.log 2>&1
grep -E "Test Case|Executed|error:" osc007.log
```

Expected: the badge rule (S3), fresh install across a foreground cycle (S1), Stop, and the
real-transport toggle (S2: listening → off → same port binds again) pass; S2 may report "skipped" if
the sandbox refuses the port, which counts as not verified.

## B. UI test (S4, < 30 s)

`-only-testing:projectM-iOSUITests/OSCNetworkAccessUITests -only-testing:projectM-iOSUITests/OSCReceiverUITests`.
Expected: enabling OSC in Settings → after closing Settings the badge reads "OSC listening on port
47124"; tap Stop → the badge disappears; Settings shows the toggle off and "Off".

## C. Regression

`swift test --package-path Packages/PerformanceControl`, `python3 scripts/check_compliance.py`,
`python3 scripts/validate_docs.py`.

## D. Device (OSC-007-T12 `{device}`, owner, last stage)

On D1 with a controller on the same Wi-Fi: turn OSC on, see the badge on the visualizer with the
port; send `/projectm/test 0.5`, see the test value; tap Stop; the badge is gone, a further message
changes nothing, Settings shows OSC off.
