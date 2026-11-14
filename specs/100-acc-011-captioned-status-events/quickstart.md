# Quickstart: ACC-011 Captioned Status Events

## Prerequisites

`xcodegen generate`; presets initialized (`git submodule update --init --depth 1 Vendor/presets/*`); an own
iOS 27.2 simulator (`xcrun simctl create "ACC11 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2`).

## A — Scripts

```bash
python3 scripts/check_status_events.py   # C2: no direct posts
python3 scripts/test_scripts.py          # includes the check's tests
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py
python3 scripts/check_motion_policy.py && python3 scripts/check_permission_catalog.py
```

## B — Unit and UI tests (simulator)

```zsh
opts=(-project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination "id=$SIM"
      -derivedDataPath .autonomous/derived-data-acc-011 CODE_SIGNING_ALLOWED=NO
      -test-timeouts-enabled YES -default-test-execution-time-allowance 180)
xcodebuild test "${opts[@]}" -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/StatusEventsUITests \
  > build.log 2>&1; grep -E "Executed|error:|failed" build.log
```

Expected: `StatusEventsTests` walks C1 and passes; `StatusEventsUITests` sees X1, X3, X21, X23 and the
caption, each test under 30 s.

## C — Device (`{device}`, D1, last stage)

VoiceOver on. Start In-App Playback, pause the track from Control Center, unplug headphones, black out and
restore, Save Frame, Record and stop, choose Camera and Stop camera, turn OSC on and Stop from the badge.
Each change is spoken once in the words shown, and camera off, OSC off and output restored show a caption.
