# Quickstart: FILE-006 Incremental Backup Manifest

1. Package tests (host): `swift test --package-path Packages/LibraryBackup --filter FolderBackup`
   (and `--filter MediaRestore`); the whole package suite must stay under a minute.
2. App build on the own simulator "FILE6" (AGENT_RULES flags), then `-only-testing:`
   `projectM-iOSTests/FolderBackupAppTests` and `projectM-iOSUITests/FolderBackupUITests`.
3. By hand (simulator): Settings › Storage › Backup › Back Up to Folder…, pick a folder in Files; again
   with no changes: the message says every asset is unchanged.
