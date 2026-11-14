# Quickstart: validating FILE-008

1. Package tests (host; Linux in CI):
   `swift test --package-path Packages/LocalPortability --filter ContentAddressedMediaFolder`,
   `swift test --package-path Packages/Compositor --filter MovieHeaderTimes`,
   `swift test --package-path Packages/LibraryBackup`.
2. App unit tests on an own iOS 27.2 simulator:
   `-only-testing:projectM-iOSTests/MediaDeduplicationTests` plus the existing PhotoStore, VideoStore,
   SceneArchiveService, LibraryBackupApp and StorageUsage tests. Expected: two identical photo imports →
   1 payload file, 2 references; same for the fixture video; release one → payload stays; release both →
   0 payloads; migration with a fault at each step → every legacy identifier resolves to its bytes.
3. UI: `-only-testing:projectM-iOSUITests/StorageUsageUITests`: the fixture container with one shared
   photo payload shows the "Shared copies … save" note.
4. Checks: `check_compliance.py`, `validate_docs.py`, `check_privacy_manifest.py <Debug .app>`.
