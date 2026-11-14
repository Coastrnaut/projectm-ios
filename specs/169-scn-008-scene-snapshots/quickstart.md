# Quickstart: SCN-008

1. `swift test --package-path Packages/SceneFormat --filter SceneSnapshot` (document, read, editing, recall plan).
2. App: `xcodegen generate`, build-for-testing on simulator "SCN8 iPhone 17", then
   `-only-testing:projectM-iOSTests/SceneSnapshotAcceptanceTests` and
   `-only-testing:projectM-iOSUITests/SceneSnapshotUITests`.
3. Manual: Settings → choose Photo, turn Glow on → Snapshots → Save Snapshot; move Intensity; tap Recall on
   "Snapshot 1"; Intensity shows its saved value and the photo does not flicker or reload.
