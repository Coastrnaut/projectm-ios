# Quickstart: SCN-006 checks

1. `swift test --package-path Packages/PresetLibrary --filter ScenePreviewStoreTests` — store, key, invalidation, retain, repair, reopen.
2. App unit tests: `-only-testing:projectM-iOSTests/ScenePreviewAcceptanceTests` — save → preview equals the injected image keyed to the hash; edit → old gone, new key; neighbours untouched; delete prunes; placeholder; relaunch.
3. UI test on "SCN6": `-only-testing:projectM-iOSUITests/ScenePreviewUITests` (`-uitestShowSeed -uitestScenePreviewFixture`): choose cue 2 in the switcher, reopen, row 2 shows `scenePreview:<id>`, row 3 a placeholder; under 30 s.
4. Repo checks (AGENT_RULES) and `check_privacy_manifest.py` on the Debug app.
