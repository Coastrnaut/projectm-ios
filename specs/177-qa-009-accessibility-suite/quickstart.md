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

Expected: 26 pass, 13 skipped (AX3), each test ≤ 30 s.

## Full matrix (adds AX3, 39 tests)

Prefix the second command with `TEST_RUNNER_QA009_FULL=1`. Expected: 39 pass.
