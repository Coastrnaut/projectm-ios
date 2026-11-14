# Quickstart: validating ANL-006

1. `swift test --package-path Packages/PerformanceControl --filter TempoConfidence` (and again with
   `-Xswiftc -DANALYSIS_NO_ACCELERATE`): state machine rules and the synthetic-PCM acceptance
   (noise, silence, 120/90 BPM pulses, tempo change). The noise test prints the largest confidence
   per input.
2. Whole suite: `swift test --package-path Packages/PerformanceControl` (< 1 minute).
3. App, on the row's simulator "ANL6 iPhone 17" (iOS 27.2): `xcodegen generate`, then
   `xcodebuild test` with `-only-testing:projectM-iOSTests`,
   `-only-testing:projectM-iOSUITests/TempoConfidenceUITests`, `.../TapTempoUITests`,
   `.../AccessibilityScreensUITests`, `.../NativeVisualUITests`, `CODE_SIGNING_ALLOWED=NO`, test
   time-outs on, output to a log file.
4. Scripts: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
   `check_permission_catalog.py`, `test_scripts.py`.
