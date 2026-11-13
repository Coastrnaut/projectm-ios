# Quickstart: ACC-001 Reduce Motion Mode

## Prerequisites

`git submodule update --init --depth 1 Vendor/presets/*`, engine and ANGLE xcframeworks built,
`xcodegen generate`, an own iOS 27.2 simulator.

## Scenario 1 — Static check

`python3 scripts/check_motion_policy.py` → `check_motion_policy: OK`; `python3
scripts/test_scripts.py` passes (includes `MotionPolicyCheckTests`).

## Scenario 2 — Unit and UI tests (simulator)

```bash
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath .autonomous/derived-data-acc-001 \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests/MotionPolicyTests -only-testing:projectM-iOSUITests/ReduceMotionUITests
```

Expected: the UI test launches with Reduce Motion on, shows and hides the controls (probe
`controls=0.00`), opens and closes Settings, toggles the simulated setting (probe `reduce=off`, next
transition `controls=0.20`) and back, and the visualization keeps running.

## Scenario 3 — Device `{device}` (owner, D1)

1. Install a Debug build on D1, start In-App Playback.
2. With Reduce Motion off, tap the visualization: the controls fade in.
3. Open Control Center or Settings → Accessibility → Motion, turn Reduce Motion on, return.
4. Tap: the controls appear and go at once. Turn VoiceOver on: controls stay until hidden (FR-070),
   labels unchanged. Leave Reduce Motion as you found it.
