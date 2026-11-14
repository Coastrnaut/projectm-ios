# Quickstart: MIDI-003 MIDI Learn

## Package (host and Linux shape)

```bash
swift test --package-path Packages/PerformanceControl --filter MIDILearnTests
swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDILearnTests
swift test --package-path Packages/LibraryBackup
```

Expected: session, eligibility, list policy, codec and value tests pass (MIDI-003-S1-S5 in the pure
model).

## App (own simulator, ≤ 10 minutes per run)

```bash
xcrun simctl create "MIDI3 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=<udid>" \
  -derivedDataPath .autonomous/derived-data-midi-003 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/MIDILearnUITests \
  -only-testing:projectM-iOSUITests/MIDIMonitorUITests -only-testing:projectM-iOSUITests/MIDIDiscoveryUITests
```

Expected: `MIDIMappingCoordinatorTests` (acceptance S1, S2, S3, S4, S6; glow under Strict S5) and the
UI test (S7: Learn → Send CC → row "CC 7 · Ch 1") pass; MIDI-002's privacy test still passes.

## Checks (S8)

```bash
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py
python3 scripts/check_motion_policy.py && python3 scripts/check_permission_catalog.py
python3 scripts/check_status_events.py && python3 scripts/test_scripts.py
python3 scripts/check_network_symbols.py <built projectM-iOS.app>
```

## Device (S9, `{device}`)

On D1 with a USB MIDI controller: turn on Listen for MIDI devices, Settings → MIDI Mappings → Learn
on Glow intensity, turn a knob: the row shows its CC and channel; with the circular spectrum and glow
on, turning the knob changes the glow; relaunch: the mapping is still listed.
