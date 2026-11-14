# Quickstart: FILE-011 Local Data Erase

1. Package tests (host): `swift test --package-path Packages/LibraryBackup --filter LibraryErase`.
2. App build and tests on an own simulator (CLAUDE.md flags), `-only-testing:` the app unit tests
   `projectM-iOSTests/LibraryEraseAppTests`, and the UI tests `LibraryEraseUITests`,
   `StorageUsageUITests`, `LibraryBackupUITests`.
3. By hand (simulator): Settings › Storage › Erase Data…, check "Scenes and show", Erase…, read the
   confirmation, Cancel (nothing pending), then again Erase at Next Launch; quit and reopen; the
   result is shown once and the show is empty; bundled presets play.
