# Quickstart: ACC-005 VoiceOver Parameter Editing

## A. Unit and table tests (Mac, own simulator)

```zsh
xcrun simctl create "ACC5 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodegen generate
opts=(-project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination "platform=iOS Simulator,id=<udid>"
      -derivedDataPath .autonomous/derived-data-acc-005 CODE_SIGNING_ALLOWED=NO
      -test-timeouts-enabled YES -default-test-execution-time-allowance 180)
xcodebuild test $opts -only-testing:projectM-iOSTests/AccessibleParameterTests > logs/acc-005/unit.log
```

Expected: formatter strings of contract C1.2, grid steps, clamps, the table test passing for all ten
controls, and one announcement for a burst of end swipes.

## B. UI test

`-only-testing:projectM-iOSUITests/VoiceOverParameterUITests`: `increment()` on the glow intensity
(50 % → 55 %, value "55 percent"), `decrement()` on the input trim (0 → "minus 1 decibel"), relaunch,
both values kept. Under 30 s.

## C. Device `{device}` (D1, owner)

VoiceOver on. Settings → pick Circular Spectrum, Glow on. For each slider (glow ×3, input trim, gate
threshold with the gate on, visual delay, and with Text/Video picked the text and loop sliders): swipe
up once and down once; hear the value with its unit change by one step; at an end hear "Maximum, …"
once. Record the result in tasks.md ACC-005-T16.
