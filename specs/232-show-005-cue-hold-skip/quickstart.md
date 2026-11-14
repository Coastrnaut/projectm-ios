# Quickstart: SHOW-005 Cue Hold and Skip

Prerequisites: worktree with `Build` symlinked, presets fetched, `xcodegen generate`, simulator "SHOW5 iPhone 17" (iOS 27.2).

1. Package: `swift test --package-path Packages/ShowControl --filter ShowSkipTests` — skip stepping, round trip, lenient read (contract K1-K3).
2. App acceptance: `xcodebuild test-without-building … -only-testing:projectM-iOSTests/CueHoldSkipAcceptanceTests` — Hold with a `ShowManualClock` (H1-H4), skip next/previous/timed, lock refusal (K4).
3. UI: `-only-testing:projectM-iOSUITests/CueHoldSkipUITests` (< 30 s) — the Hold button toggles its value; the Skip swipe marks a cue "skipped" in the editor.
