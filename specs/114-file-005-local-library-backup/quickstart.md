# Quickstart: FILE-005 Local Library Backup

1. Package tests (host, under 1 minute): `swift test --package-path Packages/LibraryBackup`
   - The acceptance: `LibraryBackupRoundTripTests` (every record kind, back up, restore into an empty
     sandbox, `LibraryRecords` equal).
   - Choices, rollback, recovery, hostile archives, exclusions: the other suites.
2. Fuzz: `swift test --package-path Packages/ImportFuzz --filter LibraryBackupFuzzTests`.
3. App and UI tests on an own iOS 27.2 simulator:
   `-only-testing:projectM-iOSTests/LibraryBackupAppTests -only-testing:projectM-iOSUITests/LibraryBackupUITests`
   (back up to a test folder, request a restore of it, relaunch with a reset library, records back).
4. By hand: Settings › Storage › Back Up Library…, save to Files; Restore from Backup…, pick it,
   Restore at Next Launch, close and reopen the app; the Backup section shows the result.
