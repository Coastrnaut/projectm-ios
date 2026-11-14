# Quickstart: UIX-005 Performance Control Layout

```bash
swift test --package-path Packages/ShowControl --filter PerformanceLayoutTests
xcodegen generate
# build-for-testing, then:
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/PerformancePadTests \
  -only-testing:projectM-iOSUITests/PerformanceLayoutUITests
```

Manual (simulator or device): start a source, tap the visualization, tap "Performance layout"; the pad
stays after the controls hide; rotate; Settings → Accessibility → Larger Text at the largest size.
Device pass with a performer: UIX-005-T13 `{device}`.
