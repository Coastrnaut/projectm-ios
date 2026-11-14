# Quickstart: ACC-003 Color-blind Friendly Controls

## Mac (simulator)

```bash
xcodegen generate
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py && python3 scripts/test_scripts.py
swift test --package-path Packages/CaptureUI --filter UIStringsTests
swift test --package-path Packages/VisualGenerators --filter VisualPaletteTests
# own simulator: xcrun simctl create "ACC3 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination "id=<udid>" \
  -only-testing:projectM-iOSTests/ColorBlindControlsTests \
  -only-testing:projectM-iOSUITests/ColorBlindControlsUITests \
  -only-testing:projectM-iOSUITests/AccessibilityScreensUITests \
  -only-testing:projectM-iOSUITests/StatusUITests CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180
```

Expected: the grayscale table passes for every group in light and dark, the control is not
distinguishable, every palette ratio meets research D2, the audit passes without the "Add Current
Scene" filter.

## D1 (`{device}`, last stage)

1. Settings → Accessibility → Display & Text Size → Color Filters → Grayscale on; Increase Contrast on.
2. Start In-App Playback; watch the indicator go active and (pause the track) silent: the symbol changes.
3. Record a few seconds and stop: record symbol → hourglass with "Finishing…".
4. Choose the Camera visual: the badge's symbol changes from starting to live.
5. Black out and restore: `eye.slash` → `eye`.
6. Check the badges have an opaque background with a border, and Settings → Show → "Add Current Scene"
   is readable.
7. Smart Invert on: the visualization is not inverted.
