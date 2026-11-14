# Quickstart: REC-010 Recording library

1. Package tests: `swift test --package-path Packages/LocalPortability` and `swift test --package-path Packages/LibraryBackup --filter LibraryErase` (categories, inventory, erase of the library folder).
2. App tests on your simulator: `xcodegen generate`, then `xcodebuild build-for-testing` and `test-without-building -only-testing:projectM-iOSTests/RecordingLibraryAcceptanceTests` (seed 3 generated recordings, delete the middle one: file gone, 2 rows in the same update, totals drop by its size; cancel keeps it; thumbnails cached; Incomplete; order; Keep; rename rules; erase category).
3. UI test: `-only-testing:projectM-iOSUITests/RecordingLibraryUITests` (< 30 s): launch with `-uitestRecordingLibrarySeed 3`, Settings › Storage › Recordings, delete one with confirmation, the summary reads 2.
4. Device `{device}`: record on D1, Keep, open Recordings, play, share to Files, delete.
