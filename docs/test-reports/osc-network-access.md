# OSC-007 OSC network access switch — test report

Spec: `specs/038-osc-007-osc-network-access-switch/` (tasks OSC-007-T01…T12). Acceptance criterion:
"Fresh install opens no listener; toggle on/off changes socket state." Date: 2026-11-13, Mac Studio,
Xcode 27.2, private iOS 27.2 simulator ("OSC7 iPhone 17", deleted afterwards). Simulator and host
results are not device evidence.

## Acceptance mapping

| Part | Test | Result |
|---|---|---|
| Default off | `SettingsTests.testOSCReceiverDefaultsPersistAndReadSafely` (OSC-001) | existing |
| Fresh install: no listener at launch | `OSCReceiverCoordinatorTests.testOffByDefaultOpensNothing` (OSC-001) | passed, 0.001 s |
| Fresh install: no listener across a background-foreground cycle | `OSCNetworkAccessTests.testFreshInstallOpensNoListenerAcrossAForegroundCycle` (new; 0 transports created) | passed, 0.002 s |
| Toggle on/off changes socket state (receiver level, real UDP) | `OSCLoopbackIntegrationTests` (OSC-001, package) | passed in the package suite |
| Toggle on/off changes socket state (the app's toggle, real system listener) | `OSCNetworkAccessTests.testToggleMovesTheRealListenerBetweenReadyAndCancelled` (new: on → `listening(port)`, off → `off` only after the cancel, a second listener binds the same port) | passed, 0.057 s (not skipped) |
| Visible listener status | `OSCNetworkAccessTests.testBadgeIsShownOnlyWhileListening`, `testBadgeFollowsTheListenerNotTheToggle`; UI test | passed |
| Stop | `OSCNetworkAccessTests.testStopFromBadgeTurnsTheSettingOffAndClosesTheListener`; UI test | passed |

## Commands

| Check | Command | Result |
|---|---|---|
| App unit tests (OSC) | `xcodebuild test … -only-testing:projectM-iOSTests/OSCNetworkAccessTests -only-testing:projectM-iOSTests/OSCReceiverCoordinatorTests` | 10 tests, 0 failures, 0.071 s |
| UI test | `-only-testing:projectM-iOSUITests/OSCNetworkAccessUITests` | passed, 18.4 s (first run failed: the VoiceOver value read "Port 47,124" from a localized interpolation; fixed with a plain String) |
| Neighbor UI test | `-only-testing:projectM-iOSUITests/OSCReceiverUITests` | passed, 21.9 s |
| App unit target | `-only-testing:projectM-iOSTests` | 138 tests, 1 failure, 3.0 s: only the known worktree failure `PresetTests.testBundledIncludedScopeMatchesRelease1_0` (preset submodules are empty in worktrees: 28 presets indexed) |
| PosterBoard | count of `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` | 32 before, 32 after the simulator runs |
| Package suite | `swift test --package-path Packages/PerformanceControl` | 73 tests, 0 failures, 1.30 s (2 s wall) |
| Compliance, docs | `check_compliance.py`, `validate_docs.py` | OK |

## Not verified (pending)

- OSC-007-T12 `{device}`: the badge and Stop on D1 with a controller on Wi-Fi (quickstart D). Owner,
  last stage.
- The chooser's badge (bottom inset) has no UI test (the UI tests autostart past the chooser); it
  is verified by the build and by reading the diff only.
- The "OSC off" VoiceOver announcement is posted but not asserted (XCUITest cannot read
  announcements).
- No red run was recorded before the implementation (tests and code were written in one step).
