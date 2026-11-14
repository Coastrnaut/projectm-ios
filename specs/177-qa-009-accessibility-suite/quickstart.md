# Quickstart: QA-009 Accessibility Snapshot Suite

## Prerequisites

`xcodegen generate`; preset submodules initialised; a free iOS 27.2 simulator (`<udid>`).

## Fast check (no simulator)

```bash
python3 scripts/qa009_manifest_check.py      # every manifest identifier exists in the app source
python3 scripts/test_scripts.py              # includes QA009ManifestTests
```

## Default subset (default size + AX5, 26 tests)

```bash
xcodebuild build-for-testing -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=<udid>" CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=<udid>" CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSUITests/PrimaryScreensAccessibilityUITests
```

Expected: 26 pass, 13 skipped (AX3). Measured 2026-11-14 on the Mac Studio (simulator QA9, load average 400-600 from other lanes): 389 s; tests 7-27 s, testStorageAX5 34.8 s.

## Full matrix (adds AX3, 39 tests)

Prefix the second command with `TEST_RUNNER_QA009_FULL=1`. Expected: 39 pass. Measured 2026-11-14: the 13 AX3 tests took 236 s (slowest testPresetBrowserAX3 33 s); run the AX3 tests as their own xcodebuild run to stay under 10 minutes per run.
