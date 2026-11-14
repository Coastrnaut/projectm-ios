# Quickstart: PRE-008 Smart Collections

1. `swift test --package-path Packages/PresetLibrary --filter PresetSmartCollection` (S1, S2).
2. `swift test --package-path Packages/LibraryBackup --filter LibraryBackupSmartCollectionTests` (S3).
3. App tests on "PRE8 iPhone 17": `-only-testing:projectM-iOSTests/PresetSmartCollectionAppTests` (S4) and
   `-only-testing:projectM-iOSUITests/PresetSmartCollectionUITests` (S5).
4. By hand: Presets → Collections → New Smart Collection → name it, pick Included, see the count, Save; open it,
   Edit Rules, add Favorites with All, see the count drop.
