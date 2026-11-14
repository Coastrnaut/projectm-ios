# Quickstart: PERF-008

1. `swift test --package-path Packages/Rendering --filter PowerProfileTests` (host).
2. App unit tests on "PERF8 iPhone 17": `-only-testing:projectM-iOSTests/PowerProfileAppTests` — acceptance:
   budgets change, `CaptureManager` snapshot identical.
3. UI test `-only-testing:projectM-iOSUITests/PowerProfileUITests`.
4. `{device}` D1: Instruments (Energy Log + Metal System Trace) 5 min Standard vs 5 min Battery saver, same preset
   and In-App Playback; the "Power profile" signpost marks the switch. Simulator results are not evidence.
