# Quickstart: MIDI-011 MIDI Hot-Plug Recovery

Run from the worktree root.

1. Package tests (host, under 1 minute):
   `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE --filter "MIDIHotplugTests|MIDIInputServiceTests|MIDIEndpointDiscoveryTests"`
   — expect the A/B fixture, collision, burst and 20-cycle tests to pass (S1-S4).
2. App unit tests on the private iOS 27.2 simulator "MIDI11 iPhone 17":
   `xcodebuild test-without-building … -only-testing:projectM-iOSTests/MIDIHotplugCoordinatorTests -only-testing:projectM-iOSTests/MIDIDiscoveryCoordinatorTests -only-testing:projectM-iOSTests/MIDIMappingCoordinatorTests -only-testing:projectM-iOSTests/MIDINoteTriggerCoordinatorTests`
   — a mapped CC changes its parameter once after a reconnect; a returning device is announced "reconnected" (S5).
3. UI tests on the DEBUG fake (each under 30 s): `-only-testing:projectM-iOSUITests/MIDIDiscoveryUITests
   -only-testing:projectM-iOSUITests/MIDIMonitorUITests` — the fake still plugs, unplugs and delivers.
4. Repository checks: compliance, docs, motion policy, permission catalog, status events, script tests, privacy
   manifest and network symbols on the Debug app.
5. `{device}`: on D1 with a USB controller mapped to a glow parameter, unplug and replug it (also quickly, under
   0.1 s if possible); the mapping keeps working and each movement acts once (the MIDI Monitor shows one event per
   message).
