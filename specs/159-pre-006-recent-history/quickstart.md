# Quickstart: PRE-006 checks

From the worktree root (Mac). Simulator: the feature's own "PRE6 iPhone 17" (iOS 27.2).

1. Package rules: `swift test --package-path Packages/PresetLibrary --filter RecentPresetHistoryTests`
   (dedup, cap, lenient read, dwell). Expect all pass in a few seconds.
2. Policy: `swift test --package-path Packages/LibraryBackup` (every key classified once; history
   erased with the collections category; never backed up).
3. App unit tests: `xcodebuild test-without-building -only-testing:projectM-iOSTests/RecentPresetsAcceptanceTests`
   (plus `LibraryBackupAppTests`, `LibraryEraseAppTests`, `PresetTests`). The acceptance test seeds
   favorites, `lastPresetID`, a tags file and history, clears, and asserts history empty with
   favorites and `lastPresetID` byte-identical and the tags file's bytes unchanged.
4. UI test: `-only-testing:projectM-iOSUITests/RecentPresetsUITests` — two presets shown 3 s each appear
   in Recently Played; Clear empties it; Favorites still lists the starred preset. Under 30 s.
5. Repo checks: `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`,
   `check_status_events`, `test_scripts`, `check_privacy_manifest` on the Debug app.

Simulator results are not device evidence; this row needs no device check.
