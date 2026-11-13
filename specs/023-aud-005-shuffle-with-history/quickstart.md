# Quickstart: AUD-005 Shuffle with history

All commands from the repository root; timings are budgets (owner rule 7), not guarantees.

1. Pure logic (host, then Linux mode):
   `swift test --package-path Packages/CaptureKit --filter 'Shuffle|PlayQueueStore'`
   `swift test --package-path Packages/CaptureKit -Xswiftc -DAUDIOCORE_NO_AVFAUDIO --filter 'Shuffle|PlayQueueStore'`
   Expect: the seed-42 sequence tests match their literal sequences; every test ≤ about 1 s.
2. Strings: `swift test --package-path Packages/CaptureUI --filter Shuffle`.
3. Whole packages on the iOS 27.2 simulator: `xcodebuild test -scheme CaptureKit` and `-scheme CaptureUI`
   from each package folder (`-test-timeouts-enabled YES -default-test-execution-time-allowance 180
   CODE_SIGNING_ALLOWED=NO`).
4. App: `xcodegen generate`, then `-only-testing:projectM-iOSUITests/ShuffleUITests` (plus
   `PlayQueueUITests`, `RepeatModeUITests`) and the app unit tests. Expect the Shuffle value "On" after a
   relaunch, "Off" after turning it off from the transport.
5. `{device}`: on D1, shuffle a queue of five tracks during playback with a Bluetooth route change and a
   phone-call interruption; Shuffle changes never cut audio (AUD-005-R15). Simulator results are not
   device evidence.
