# Quickstart: UIX-002 Quick Scene Switcher

Simulator only; never device evidence.

## Prerequisites

```bash
cd <worktree>
git submodule update --init --depth 1 Vendor/presets/*   # if missing
xcodegen generate
xcrun simctl create "UIX2 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
```

## Unit tests (filter, highlight, probe)

```bash
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=<udid>" \
  -derivedDataPath .autonomous/derived-data-uix-002 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests > uix2-unit.log 2>&1
grep -E "Executed|error:|failed" uix2-unit.log | tail
```

Expected: `SceneSwitcherTests` pass (case, diacritics, empty query, ordering, highlight, reopen,
probe with a fake clock, 256-cue filter < 5 ms).

## UI tests

`-only-testing:projectM-iOSUITests/SceneSwitcherUITests` plus `ShowCueUITests` and
`SceneRepairUITests` (regression). Expected:

1. Seeded show: open with the Scenes button, the field has keyboard focus; type "dr": only "Drop";
   focus kept; Return → `showAppliedScene` = scene 3, `sceneSwitcherProbe` = `applied|…|ok`.
2. Type "b", "r", delete: the field keeps focus and text after every change; Escape; ⌘K reopens
   with the abandoned query.
3. Repair seed: choose "Broken" → the repair report appears, nothing applied; probe `repairShown|…|ok`.

## Scripts

```bash
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py && \
python3 scripts/check_motion_policy.py && python3 scripts/check_permission_catalog.py && \
python3 scripts/check_status_events.py && python3 scripts/test_scripts.py
```
