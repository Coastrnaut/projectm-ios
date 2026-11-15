# Quickstart: PRE-017 validation

1. `swift test --package-path Packages/PresetLibrary --filter UserPresetHistoryTests` — revert sha match and file-set diff (S1), bounds and reference counting (S2), migration, newer/unreadable list, failed save (S3).
2. `swift test --package-path Packages/LibraryBackup --filter LibraryBackupPresetVersionTests` — backup and restore keep versions (S4).
3. App UI test on "PRE17 iPhone 17": `-only-testing:projectM-iOSUITests/UserPresetVersionsUITests` — revert a seeded preset from the Versions sheet (S5).
