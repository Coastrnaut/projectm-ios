# Quickstart: ACC-006 Dynamic Type inspector

## Simulator (the Mac)

```bash
xcodegen generate
opts=(-project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination "platform=iOS Simulator,id=<udid>"
      -derivedDataPath <dd> CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180)
xcodebuild build-for-testing $opts > build.log 2>&1
xcodebuild test-without-building $opts -only-testing:projectM-iOSUITests/DynamicTypeInspectorUITests > inspector.log 2>&1
grep -E "Test Case .*(passed|failed)|Executed" inspector.log
```

Survey at another size (every issue listed, screenshots kept for failing screens):

```bash
TEST_RUNNER_ACC006_SIZE=UICTContentSizeCategoryAccessibilityM TEST_RUNNER_ACC006_SURVEY=1 \
  xcodebuild test-without-building $opts -only-testing:projectM-iOSUITests/DynamicTypeInspectorUITests/testSettingsAX5 > s.log 2>&1
```

Sizes (UIKit names): AX1 `UICTContentSizeCategoryAccessibilityM`, AX2 `…AccessibilityL`, AX3
`…AccessibilityXL` (the suite's middle size), AX4 `…AccessibilityXXL`, AX5 `…AccessibilityXXXL`; the
largest standard size is `UICTContentSizeCategoryXXXL`.

## Device (ACC-006-T12, `{device}`, last)

1. On D1: Settings › Accessibility › Display & Text Size › Larger Text: on, slider at the far right
   (AX5). Open the app; walk the screens of contract C1: notice (fresh install), chooser, controls
   with In-App Playback (scroll the controls), Settings to Licenses, browser, Collections, My Presets,
   a pack, show editor and Rename Scene, preset editor on a copy, a repair report (if a show seed is
   not available, skip and note it), camera notice (deny camera), guide.
2. Record per screen: clipped text (yes/no), every button tapped (yes/no), fields typed (yes/no).
3. Repeat the controls, Settings and browser on an iPad (D2 or D3) at AX5, portrait and landscape.
4. Write the result in `docs/test-reports/accessibility-dynamic-type.md` (D1, iPad, date, iOS).
