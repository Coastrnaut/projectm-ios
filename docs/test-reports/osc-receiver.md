# OSC-001 OSC receiver — test report

Spec: `specs/032-osc-001-osc-receiver/` (tasks OSC-001-T01…T26). Acceptance criterion: "Valid OSC
float packet updates test value and disable closes listener." Date: 2026-11-13, Mac Studio, Xcode
27.2. Simulator and host results are not device evidence.

## Verified

| Check | Command | Result |
|---|---|---|
| Package suite, macOS host | `swift test --package-path Packages/PerformanceControl` | 58 tests, 0 failures, 1.33 s (4.3 s wall); fuzz of 20,000 packets 0.065 s |
| Loopback acceptance, macOS host | same (`OSCLoopbackIntegrationTests`) | passed 5 of 5 runs, 0.51-0.53 s each (0.5 s is the inverted wait after disable) |
| Package suite, iOS 27.2 simulator | `xcodebuild test -scheme PerformanceControl` (private simulator) | 58 tests, 0 failures, 4.0 s; loopback test 0.72 s |
| App unit tests | `xcodebuild test … -only-testing:projectM-iOSTests/{OSCReceiverCoordinatorTests,SettingsTests,ParameterCatalogAppTests,TempoCoordinatorTests}` | 21 tests, 0 failures, each ≤ 0.03 s |
| UI test | `-only-testing:projectM-iOSUITests/OSCReceiverUITests` | passed, 14.8 s (21.8 s on the first run) |
| Neighbor UI test | `SettingsUITests/testPerformanceOverlay` | passed, 9.4 s |
| Compliance | `python3 scripts/check_compliance.py` | OK (Network framework only under `OSCTransport/`) |
| Docs, scripts | `validate_docs.py`, `test_scripts.py` | OK; 99 script tests OK (1 skipped) |
| No sender in Release | `swift build -c release` + `nm` | Release objects: 0 `OSCLoopbackSender` symbols and no `NWConnection(host:port:)` reference; Debug: 17 sender symbols |
| PosterBoard | count of `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` | 32 before, 32 after the simulator runs |

What the loopback test proves (OSC-001-S1, S2): a real UDP listener on a free port receives
`/projectm/test ,f 0.42` from 127.0.0.1 and the test value becomes 0.42; after disable the receiver
reports `off` only after the listener is cancelled, a second packet changes nothing, and a new
listener binds the same port. The value is applied off the main thread.

## Finding during implementation

`NWParameters.acceptLocalOnly = true` (planned as an extra local-only layer) made the iOS 27.2
simulator drop the loopback datagram (all receiver counters 0) while the macOS host delivered it.
The flag's rule is not documented, so it was removed; the app's own tested rule
(`OSCPeerAddress.isLocal`, research OSC-001-D2) decides which peers are read. Whether a device
admits a LAN peer is part of the device task.

## Not verified (pending)

- OSC-001-T26 `{device}`: a controller on another computer on Wi-Fi sends to D1; the Local Network
  permission prompt; turning OSC off stops changes. Owner, last stage (quickstart D).
- Not exercised over a real network: dropping a non-local peer, evicting the ninth peer, and the
  port-in-use and Local Network-denied error mappings (their rules are unit-tested; the mappings
  are not).
- Linux: the package's OSC code is written to compile there (the transport and loopback test are
  behind `#if canImport(Network)`), but it was not built on Linux here; CI's Linux job checks it.
- The UI test logged two XCTest runtime warnings ("Invalid frame dimension", "UI unresponsiveness"
  from an activation call); the test passed and the cause was not investigated.
