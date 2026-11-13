# Quickstart: validating AUD-004

## A. Package tests (macOS host; Linux for the pure parts)

```bash
swift test --package-path Packages/CaptureKit --filter 'Repeat|PlayQueue|Queue'
swift test --package-path Packages/CaptureKit -Xswiftc -DAUDIOCORE_NO_AVFAUDIO   # pure logic
swift test --package-path Packages/CaptureUI
```

Expected: `RepeatPipelineTests` (AUD-004-S1 to S3), `RepeatTransportTests`, `RepeatModeTests`,
`PlayQueueStoreTests` and the AUD-003/AUD-006/QA-007 suites pass.

## B. Simulator (iOS 27.2)

From each package folder: `xcodebuild test -scheme CaptureKit` (and `CaptureUI`) with
`-destination 'id=<udid>' -test-timeouts-enabled YES -default-test-execution-time-allowance 180
CODE_SIGNING_ALLOWED=NO`, output to a log file.

App: `xcodegen generate`, then `xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS
-destination 'id=<udid>' -derivedDataPath .build/dd CODE_SIGNING_ALLOWED=NO
-only-testing:projectM-iOSUITests/RepeatModeUITests` (and the other suites named in tasks.md).
Expected: each mode set from the UI is shown again after a relaunch (AUD-004-S4).

## C. Device (`{device}`, owner phase)

On D1, with three imported tracks: Off ends after the last track and shows Stopped at the first
track's 0:00; One Track repeats without an audible gap through wired and Bluetooth routes; a phone
call interruption during One Track resumes per AUD-014. Simulator and offline results are not
device evidence.
