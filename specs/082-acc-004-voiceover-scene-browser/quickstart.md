# Quickstart: ACC-004 validation

Prerequisites: preset submodules (`git submodule update --init --depth 1 Vendor/presets/*`),
`xcodegen generate`, an own iOS 27.2 simulator.

```zsh
args=(-project ProjectM-iOS.xcodeproj -scheme projectM-iOS
      -destination "platform=iOS Simulator,id=<udid>"
      -derivedDataPath .autonomous/derived-data-acc-004 CODE_SIGNING_ALLOWED=NO
      -test-timeouts-enabled YES -default-test-execution-time-allowance 180)
xcodebuild build-for-testing $args > build.log 2>&1
xcodebuild test-without-building $args -only-testing:projectM-iOSTests > unit.log 2>&1
xcodebuild test-without-building $args -only-testing:projectM-iOSUITests/AccessibilityScreensUITests > ui.log 2>&1
```

Expected: unit tests pass (AccessibilityAnnouncerTests included); every AccessibilityScreensUITests
test passes in under 30 s with zero unfiltered audit issues.

Scripts: `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`,
`python3 scripts/check_motion_policy.py`, `python3 scripts/check_permission_catalog.py`.

Device (`{device}`, owner, D1): VoiceOver on; walk the controls, the show editor (seeded or a real
show), the preset browser, Collections and My Presets; check every control is reachable and named,
the actions rotor on a cue and a preset row, and the C1 announcements without repeats.
