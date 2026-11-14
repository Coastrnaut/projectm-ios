# Quickstart: SHOW-004 Cue Transition Override

Prerequisites: the worktree's `Build` symlink, `xcodegen generate`, simulator "SHOW4 iPhone 17" (iOS 27.2).

1. Package: `swift test --package-path Packages/ShowControl --filter ShowTransitionOverrideTests` — round trip, bytes without overrides, lenient read, edit and duplicate rules.
2. App acceptance: `xcodebuild test-without-building … -only-testing:projectM-iOSTests/CueTransitionOverrideAcceptanceTests` — two cues of one scene with a 2 s crossfade default; a Cut override on the first; stepping drives a cut then the crossfade; the scene file bytes and both defaults are unchanged; the lock refuses the edit.
3. UI: `-only-testing:projectM-iOSUITests/CueTransitionOverrideUITests` (< 30 s) — "Transition Into This Cue…" → Cut shows "Into this cue: Cut"; "Use Scene Default" removes it.
