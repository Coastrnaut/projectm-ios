# Quickstart: MIDI-002 MIDI Input Monitor

## Package (host and Linux shape)

```bash
swift test --package-path Packages/PerformanceControl --filter MIDI
swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDI
```

Expected: decoder tables, ring overflow and fixed storage, service lifecycle and texts pass.

## App (own simulator)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,id=<MIDI2 udid>' \
  -derivedDataPath .autonomous/derived-data-midi-002 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/MIDIDiscoveryUITests \
  -only-testing:projectM-iOSUITests/MIDIMonitorUITests
```

Expected: `MIDIMonitorCoordinatorTests` pass (acceptance and privacy scan); the UI test reads a
"Control change, channel 1, controller 7, value 100" row and a "Note on, channel 1, note 60 C4,
velocity 100" row in under 30 s.

## Checks

`check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`,
`check_status_events.py`, `test_scripts.py`, `check_network_symbols.py <app>`,
`check_privacy_manifest.py <app>`.

## Device (S8, `{device}`)

D1 or D2 with a class-compliant USB controller: listening on, open Settings → MIDI Monitor, move a
fader (control change rows with the right controller and value) and play a key (note on, then note
off); close the monitor and confirm it reopens empty.
