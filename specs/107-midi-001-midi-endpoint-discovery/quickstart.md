# Quickstart: MIDI-001 checks

Budgets (owner rule 7): unit tests about 1-2 s, package suite under 1 minute, UI test under 30 s.

1. Package (host): `swift test --package-path Packages/PerformanceControl --filter MIDI` — identity,
   diff, coalescer and discovery tests pass (S1-S5).
2. Package (Linux shape, on the Mac): `swift test --package-path Packages/PerformanceControl
   -Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDI`.
3. Scripts: `python3 scripts/test_scripts.py`, `check_compliance.py`, `validate_docs.py`,
   `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`.
4. App, own simulator (`xcrun simctl create "MIDI1 iPhone 17" "iPhone 17"
   com.apple.CoreSimulator.SimRuntime.iOS-27-2`), after `xcodegen generate`:
   `xcodebuild test -scheme projectM-iOS -destination id=<udid>
   -derivedDataPath .autonomous/derived-data-midi-001 CODE_SIGNING_ALLOWED=NO
   -test-timeouts-enabled YES -default-test-execution-time-allowance 180
   -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/OSCReceiverUITests
   -only-testing:projectM-iOSUITests/MIDIDiscoveryUITests` (S6).
5. Binary scan: `python3 scripts/check_network_symbols.py <derived>/Build/Products/Debug-iphonesimulator/projectM-iOS.app`
   and `python3 scripts/check_privacy_manifest.py` (S7).
6. `{device}` (S8): on D1 or D2 with a class-compliant USB MIDI controller: turn on "Listen for MIDI
   devices", plug the controller: it appears within 1 s as Input and Output; unplug: it leaves;
   replug: it returns (same rows). Note what transport the system reports (research MIDI-001-D5).
