# Quickstart: SCN-005 Scene Tags

All checks run on the Mac (simulator "SCN5"); none are device evidence.

1. `swift test --package-path Packages/ShowControl --filter 'SceneTag|ShowTag'` — tag rules, round trip,
   legacy bytes, repair.
2. `swift test --package-path Packages/LibraryBackup --filter LibraryBackupSceneTagTests` — backup
   round trip keeps tags.
3. App unit tests: `-only-testing:projectM-iOSTests/SceneTagAcceptanceTests` and
   `-only-testing:projectM-iOSTests/SceneSwitcherTests` — tag, filter, change, reload from disk.
4. UI test: `-only-testing:projectM-iOSUITests/SceneTagsUITests` (< 30 s) — ⌘K, tag button on cue 1,
   add "Intro", Done, select the "Intro" chip: only cue 1 is listed.
5. Repo checks (AGENT_RULES): compliance, docs, motion, permissions, status events, script tests.
