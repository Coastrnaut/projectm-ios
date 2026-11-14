# Quickstart: SCN-007

1. `swift test --package-path Packages/ShowControl` (transition document tests).
2. `swift test --package-path Packages/Compositor --filter SceneTransition` (curve on spec, clock and bus).
3. `swift test --package-path Packages/LibraryBackup --filter Transition` (backup round trip).
4. App: `xcodegen generate`, build-for-testing on simulator "SCN7", then
   `-only-testing:projectM-iOSTests/CueTransitionAcceptanceTests` and
   `-only-testing:projectM-iOSUITests/CueTransitionUITests`.
5. Manual: Settings → Show → swipe a cue right → Transition; choose Crossfade, 1.5 s, Ease Out; relaunch; the row reads "Transition: Crossfade 1.5 s, Ease Out".
