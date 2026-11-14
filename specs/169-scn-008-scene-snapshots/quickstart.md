# Quickstart: SCN-008

1. `swift test --package-path Packages/SceneFormat --filter SceneSnapshot` (document, read, editing, recall plan).
2. App: `xcodegen generate`, build-for-testing on simulator "SCN8 iPhone 17", then
   `-only-testing:projectM-iOSTests/SceneSnapshotAcceptanceTests` and
   `-only-testing:projectM-iOSUITests/SceneSnapshotUITests`.
3. Manual: Settings → choose Circular Spectrum, turn Glow on → Save Snapshot (under the glow sliders); move
   Intensity; tap Recall on "Snapshot 1"; Intensity shows its saved value. On Photo, recall leaves the photo as it is.
